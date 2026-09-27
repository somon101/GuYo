"""How users move within their own rank: the "↑3 / ↓2" arrows on the
rating boards and the "you moved N places" notifications.

A place changes not only when a user earns points but when OTHERS do --
someone overtaking you moves you down without you doing anything. So
nothing here hangs off a points award. sync_rank_positions recomputes
every user's live place from UserRating (the same order the own-rank
board uses: points desc, then user_id), compares it with the last stored
UserRankPosition, and records the move. It runs from the background
scheduler every minute and at the start of every rating read, so what a
user sees is never more than a moment old.
"""

import logging
import time
from datetime import datetime, timedelta

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.dates import utc_now
from app.database import SessionLocal
from app.models.rating import Rank, UserRankPosition, UserRating
from app.models.user import User
from app.notifications import send_notification
from app.rating.service import get_rating_settings, ordered_enabled_ranks

# How long an arrow stays up after the move it describes.
ARROW_LIFETIME = timedelta(hours=24)

# Rating reads call sync_rank_positions too; this keeps a burst of them
# (several people opening Рейтинг at once) from each recomputing every
# place. The scheduler's minute tick is far above it.
MIN_SECONDS_BETWEEN_SYNCS = 5.0

# Any fixed number, the same for every process: only one sync may run at
# a time, so two can never both see "moved 5 places" and both notify.
_ADVISORY_LOCK_KEY = 7_314_001

NOTIFICATION_SOURCE = "rank_move"

logger = logging.getLogger(__name__)

_last_sync_at = 0.0


def _places(n: int) -> str:
    n = abs(n)
    if n % 10 == 1 and n % 100 != 11:
        return "место"
    if n % 10 in (2, 3, 4) and n % 100 not in (12, 13, 14):
        return "места"
    return "мест"


def _rank_for(ranks: list[Rank], points: int) -> Rank | None:
    """current_rank_for_points over an already-fetched ladder -- same
    comparison, same order, without a query per user."""
    for rank in ranks:
        if rank.min_points <= points and (rank.max_points is None or points <= rank.max_points):
            return rank
    return None


def live_positions(db: Session) -> dict[int, tuple[Rank, int]]:
    """user_id -> (their rank, their 1-based place in it), for everyone
    who currently has a rank."""
    ranks = ordered_enabled_ranks(db)
    ratings = db.query(UserRating).order_by(UserRating.total_points.desc(), UserRating.user_id.asc()).all()
    counters: dict[int, int] = {}
    result: dict[int, tuple[Rank, int]] = {}
    for rating in ratings:
        rank = _rank_for(ranks, rating.total_points)
        if rank is None:
            continue
        counters[rank.id] = counters.get(rank.id, 0) + 1
        result[rating.user_id] = (rank, counters[rank.id])
    return result


def sync_rank_positions(db: Session, *, force: bool = False) -> bool:
    """Brings every UserRankPosition up to date and sends any move
    notifications that are due. Commits its own work. Returns False when
    it didn't run: throttled (unless `force`), or another sync holds the
    lock -- in both cases the result is at most a few seconds old anyway."""
    global _last_sync_at
    if not force and time.monotonic() - _last_sync_at < MIN_SECONDS_BETWEEN_SYNCS:
        return False
    if not db.execute(text("SELECT pg_try_advisory_xact_lock(:key)"), {"key": _ADVISORY_LOCK_KEY}).scalar():
        db.rollback()
        return False
    _last_sync_at = time.monotonic()

    now = utc_now()
    threshold = get_rating_settings(db).rank_move_notify_threshold
    live = live_positions(db)
    rows = {row.user_id: row for row in db.query(UserRankPosition).all()}

    notify: list[tuple[int, int, int, Rank]] = []  # (user_id, from, to, rank)
    for user_id, (rank, position) in live.items():
        row = rows.pop(user_id, None)
        if row is None:
            db.add(UserRankPosition(user_id=user_id, rank_id=rank.id, position=position, notified_position=position))
            continue
        if row.rank_id != rank.id:
            # A new rank is a new ladder: start over, no arrow, no alert.
            row.rank_id = rank.id
            row.position = position
            row.previous_position = None
            row.changed_at = now
            row.notified_position = position
            continue
        moved_from = None
        if position != row.position:
            moved_from = row.position
            row.previous_position = row.position
            row.position = position
            row.changed_at = now
        if threshold > 0:
            # One big move is announced as itself -- the same number the
            # arrow shows. Small moves that add up (overtaken one place at
            # a time) are announced once they total `threshold` since the
            # last announcement.
            if moved_from is not None and abs(moved_from - position) >= threshold:
                notify.append((user_id, moved_from, position, rank))
                row.notified_position = position
            elif abs(row.notified_position - position) >= threshold:
                notify.append((user_id, row.notified_position, position, rank))
                row.notified_position = position

    # Whoever is left no longer has a rank at all (points below every
    # range, or their rank was disabled): nothing to track.
    for row in rows.values():
        db.delete(row)

    if notify:
        users = {u.id: u for u in db.query(User).filter(User.id.in_([n[0] for n in notify])).all()}
        for user_id, before, after, rank in notify:
            user = users.get(user_id)
            if user is None:
                continue
            moved = before - after
            if moved > 0:
                body = (
                    f"Отлично! Вы поднялись на {moved} {_places(moved)} в ранге «{rank.name}» — "
                    f"теперь вы {after}-й."
                )
            else:
                body = (
                    f"Вас обогнали: вы опустились на {-moved} {_places(moved)} в ранге «{rank.name}» — "
                    f"теперь вы {after}-й. Позанимайтесь, чтобы вернуть позицию!"
                )
            send_notification(db, user, body, title="Рейтинг", source=NOTIFICATION_SOURCE)

    db.commit()
    return True


def refresh_rank_positions(*, force: bool = False) -> None:
    """sync_rank_positions in a session of its own, never raising -- what
    the scheduler and the rating endpoints call. Its own session so that
    its commit (or its rollback when another sync holds the lock) never
    touches whatever the calling request has in flight."""
    db = SessionLocal()
    try:
        sync_rank_positions(db, force=force)
    except Exception:
        logger.exception("rank position sync failed")
        db.rollback()
    finally:
        db.close()


def position_changes(db: Session, user_ids: list[int], *, now: datetime | None = None) -> dict[int, int]:
    """user_id -> places moved in their latest move, for those whose
    latest move is less than ARROW_LIFETIME old. Positive is up."""
    if not user_ids:
        return {}
    since = (now or utc_now()) - ARROW_LIFETIME
    rows = (
        db.query(UserRankPosition)
        .filter(
            UserRankPosition.user_id.in_(user_ids),
            UserRankPosition.previous_position.is_not(None),
            UserRankPosition.changed_at >= since,
        )
        .all()
    )
    return {
        row.user_id: row.previous_position - row.position
        for row in rows
        if row.previous_position != row.position
    }
