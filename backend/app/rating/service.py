"""Seasonal rating's own service layer -- entirely separate from
app/achievements/. Nothing here reads or writes Achievement/UserAchievement,
and nothing in app/achievements/ reads or writes any model imported below.
"""

from datetime import datetime

from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dates import utc_now
from app.models.rating import (
    RESET_MODE_FIXED,
    SEASON_ACTIVE,
    SEASON_COMPLETED,
    SEASON_SCHEDULED,
    Rank,
    RatingSettings,
    Season,
    SeasonHistory,
    UserRating,
    UserWordPoints,
)
from app.models.user import User


def get_rating_settings(db: Session) -> RatingSettings:
    """Same "single row, always id=1" idiom as LearningSettings -- created
    lazily with defaults on first read rather than requiring a migration
    data-seed."""
    settings = db.get(RatingSettings, 1)
    if settings is None:
        settings = RatingSettings(id=1)
        db.add(settings)
        db.flush()
    return settings


def get_or_create_user_rating(db: Session, user_id: int) -> UserRating:
    rating = db.query(UserRating).filter(UserRating.user_id == user_id).first()
    if rating is None:
        rating = UserRating(user_id=user_id, total_points=0)
        db.add(rating)
        db.flush()
    return rating


def grant_rating_points(db: Session, user: User, points: int) -> None:
    """The one other place (besides award_word_points_if_new) rating
    points ever get added -- used by the Quest system's own reward on
    successful completion (see app/quests/service.py). Deliberately NOT
    deduplicated the way word-points are (no "once per X" ledger here):
    a quest's daily one-word-per-day limit is enforced entirely on the
    Quest side (UserQuestWordDay), not by this generic grant function,
    which just applies whatever point delta it's given."""
    rating = get_or_create_user_rating(db, user.id)
    rating.total_points += points
    db.flush()


def ordered_enabled_ranks(db: Session) -> list[Rank]:
    """Every enabled rank, in the admin's own `order` (then `id` as a
    stable tie-break) -- the one ladder both `current_rank_for_points`
    (fetch once, reuse per lookup) and the "Все уровни" full-ladder screen
    (app/routers/rating.py's GET /rating/ranks) read from, so the two can
    never disagree about how many ranks there are or what order they're
    in."""
    return db.query(Rank).filter(Rank.enabled.is_(True)).order_by(Rank.order, Rank.id).all()


def current_rank_for_points(db: Session, points: int) -> Rank | None:
    """The one place a user's rank is ever determined -- purely a
    comparison against enabled Ranks' own [min_points, max_points] ranges,
    never a stored/cached value that could drift from `points`. Returns
    None (rather than raising) if no enabled rank's range covers `points`,
    e.g. a gap left by admin misconfiguration -- the UI shows a neutral
    "no rank yet" state instead of breaking.

    assert_rank_range_free already refuses to let two enabled ranks'
    ranges overlap, so ordered_enabled_ranks's ordering is normally never
    actually decisive here, but it gives a defined, non-arbitrary answer
    rather than "whatever order the database happened to return" if a
    conflict ever slips through (e.g. a row edited directly outside the
    API)."""
    for rank in ordered_enabled_ranks(db):
        if rank.min_points <= points and (rank.max_points is None or points <= rank.max_points):
            return rank
    return None


def next_rank_for_points(db: Session, points: int) -> Rank | None:
    """The lowest-`min_points` enabled rank still above the user's current
    points -- what a progress-to-next-rank bar climbs toward. None if the
    user is already at (or above) the highest enabled rank."""
    return (
        db.query(Rank)
        .filter(Rank.enabled.is_(True), Rank.min_points > points)
        .order_by(Rank.min_points.asc())
        .first()
    )


def ranks_overlap(a_min: int, a_max: int | None, b_min: int, b_max: int | None) -> bool:
    a_hi = a_max if a_max is not None else float("inf")
    b_hi = b_max if b_max is not None else float("inf")
    return a_min <= b_hi and b_min <= a_hi


def assert_rank_range_free(
    db: Session, *, min_points: int, max_points: int | None, enabled: bool, exclude_id: int | None = None
) -> None:
    """Raises ValueError if an enabled rank with this range would overlap
    another already-enabled rank's range. A disabled rank is never
    checked -- it plays no part in current_rank_for_points, so its range
    can't actually conflict with anything live."""
    if not enabled:
        return
    query = db.query(Rank).filter(Rank.enabled.is_(True))
    if exclude_id is not None:
        query = query.filter(Rank.id != exclude_id)
    for other in query.all():
        if ranks_overlap(min_points, max_points, other.min_points, other.max_points):
            raise ValueError(f"Диапазон пересекается с рангом «{other.name}»")


def award_word_points_if_new(db: Session, user: User, word_id: int) -> None:
    """Grants this user rating points for `word_id` at most once, ever --
    the UserWordPoints unique constraint is what actually guarantees that
    at the database level. Safe to call every time a word's `is_learned`
    check passes (the same "safe to call defensively/often" contract
    app/achievements/service.py's check_and_grant_achievements already
    uses): a word that was already awarded is simply skipped, so this
    never double-counts no matter how many times it's called for the same
    (user, word).

    `points_awarded` snapshots RatingSettings.points_per_learned_word at
    this exact moment -- a later admin change to that setting only ever
    affects future awards, never this one.

    The pre-check below narrows the common case, but two truly
    simultaneous requests for the same (user, word) could both pass it --
    the UNIQUE(user_id, word_id) constraint is what actually decides that
    at the database level. The insert runs in its own SAVEPOINT so a
    losing request's IntegrityError only rolls back this one insert (not
    the rest of the caller's transaction, e.g. the WordProgress update
    already made in the same request) and returns quietly, exactly as if
    this word had already been awarded -- never a 500 for the loser, and
    never double-counted points either way."""
    already_awarded = (
        db.query(UserWordPoints).filter(UserWordPoints.user_id == user.id, UserWordPoints.word_id == word_id).first()
        is not None
    )
    if already_awarded:
        return

    settings = get_rating_settings(db)
    points = settings.points_per_learned_word

    try:
        with db.begin_nested():
            db.add(UserWordPoints(user_id=user.id, word_id=word_id, points_awarded=points))
            db.flush()
    except IntegrityError:
        return

    rating = get_or_create_user_rating(db, user.id)
    rating.total_points += points
    db.flush()


LEADERBOARD_LIMIT = 100


def leaderboard_for_rank(db: Session, rank: Rank, limit: int = LEADERBOARD_LIMIT) -> list[UserRating]:
    """Top `limit` users whose CURRENT points fall inside this one rank's
    own range -- never a manually-picked rank, always the caller's own
    (see app/routers/rating.py). Filters directly on UserRating.total_points
    rather than computing every user's rank in Python, since a rank's
    range already says exactly which point values belong to it."""
    query = db.query(UserRating).filter(UserRating.total_points >= rank.min_points)
    if rank.max_points is not None:
        query = query.filter(UserRating.total_points <= rank.max_points)
    return query.order_by(UserRating.total_points.desc(), UserRating.user_id.asc()).limit(limit).all()


def rank_position_for_user(db: Session, rank: Rank, rating: UserRating) -> int:
    """This user's own 1-based place among everyone currently in the SAME
    rank -- the real position, not capped at the leaderboard's top-100
    (a user sitting 250th in their rank gets 250, not "off the board").
    Ordered exactly like leaderboard_for_rank does (points desc, then
    user_id asc as the tie-break), so the number shown on the Profile
    screen always matches where that user actually appears on the
    "Топ-100" board itself."""
    query = db.query(func.count(UserRating.user_id)).filter(UserRating.total_points >= rank.min_points)
    if rank.max_points is not None:
        query = query.filter(UserRating.total_points <= rank.max_points)
    ahead = query.filter(
        (UserRating.total_points > rating.total_points)
        | ((UserRating.total_points == rating.total_points) & (UserRating.user_id < rating.user_id))
    ).scalar()
    return (ahead or 0) + 1


def leaderboard_global(db: Session, limit: int = LEADERBOARD_LIMIT) -> list[UserRating]:
    """Top `limit` users across every rank combined, by points alone."""
    return db.query(UserRating).order_by(UserRating.total_points.desc(), UserRating.user_id.asc()).limit(limit).all()


def get_active_season(db: Session) -> Season | None:
    return db.query(Season).filter(Season.status == SEASON_ACTIVE).first()


# --- Season periods and their lifecycle --------------------------------------
#
# Every season owns a half-open period [starts_at, ends_at): the end moment
# belongs to the NEXT season, not this one. That is exactly what makes
# "season A ends at the same moment season B begins" a legal, conflict-free
# schedule rather than an overlap -- and it is the same rule both the
# overlap check and sync_season_states below apply, never two.


def seasons_overlap(
    a_start: datetime,
    a_end: datetime | None,
    b_start: datetime,
    b_end: datetime | None,
) -> bool:
    """True if two half-open periods share any moment. A null end means
    "open-ended", i.e. it covers everything from its start onward."""
    a_open = a_end is None
    b_open = b_end is None
    if a_open and b_open:
        return True
    if a_open:
        return b_end > a_start
    if b_open:
        return a_end > b_start
    return a_start < b_end and b_start < a_end


def assert_season_period_free(
    db: Session, *, starts_at: datetime, ends_at: datetime | None, exclude_id: int | None = None
) -> None:
    """Raises ValueError if this period would collide with a season that
    hasn't finished yet. Completed seasons are never checked -- their
    period is history and cannot conflict with anything live.

    An open-ended season (no `ends_at`) gets its own message: nothing can
    be scheduled after it, because nothing can know when it frees up. The
    fix is for the admin to give that season an end moment first, not for
    this code to guess one -- ending a season resets every user's points,
    so it must never happen as a side effect of creating another."""
    if ends_at is not None and ends_at <= starts_at:
        raise ValueError("Дата окончания должна быть позже даты начала")

    query = db.query(Season).filter(Season.status != SEASON_COMPLETED)
    if exclude_id is not None:
        query = query.filter(Season.id != exclude_id)
    for other in query.order_by(Season.starts_at).all():
        if not seasons_overlap(starts_at, ends_at, other.starts_at, other.ends_at):
            continue
        if other.ends_at is None:
            raise ValueError(
                f"У сезона «{other.name}» не задана дата окончания — "
                "укажите её, чтобы запланировать следующий сезон"
            )
        raise ValueError(f"Период пересекается с сезоном «{other.name}»")


def sync_season_states(db: Session, now: datetime | None = None) -> bool:
    """The ONE place a season's status ever changes on its own. Idempotent
    and safe to call as often as anything likes: it compares the stored
    periods against `now` and does only what is actually due.

    In order, because the order is what makes "A ends exactly when B
    starts" come out right:
      1. an active season whose `ends_at` has arrived is ended -- with its
         SCHEDULED end recorded as the real end moment, so a backend that
         was down over that moment still writes truthful history rather
         than "ended whenever we noticed";
      2. a scheduled season whose whole period already elapsed is closed
         without any reset or history: it was never the live season, so
         nobody earned anything in it and nobody's points may be touched
         for it;
      3. the earliest scheduled season whose start has arrived becomes
         active -- only ever when no active season is left, which step 1
         has just guaranteed for a back-to-back schedule.

    Returns True if anything changed. Because every decision comes from
    stored columns, a restart resumes exactly where it left off -- none of
    this lives in memory."""
    now = now or utc_now()
    changed = False

    # Locked, not just read: the background sweep and a request handler can
    # both land here at the same moment, and ending a season twice would
    # try to write every user's history row twice. The second caller blocks
    # here until the first commits, then re-evaluates the filter and finds
    # no active season at all -- so it simply moves on.
    active = db.query(Season).filter(Season.status == SEASON_ACTIVE).with_for_update().first()
    if active is not None and active.ends_at is not None and active.ends_at <= now:
        end_season(db, active, at=active.ends_at)
        changed = True

    expired = (
        db.query(Season)
        .filter(
            Season.status == SEASON_SCHEDULED,
            Season.ends_at.is_not(None),
            Season.ends_at <= now,
        )
        .all()
    )
    for season in expired:
        season.status = SEASON_COMPLETED
        season.ended_at = season.ends_at
        changed = True
    if expired:
        db.commit()

    if get_active_season(db) is None:
        due = (
            db.query(Season)
            .filter(Season.status == SEASON_SCHEDULED, Season.starts_at <= now)
            .order_by(Season.starts_at, Season.id)
            .with_for_update()
            .first()
        )
        if due is not None:
            due.status = SEASON_ACTIVE
            db.commit()
            changed = True

    return changed


def apply_season_reset(points: int, settings: RatingSettings) -> int:
    """Never negative -- 0 is the floor regardless of reset mode or how
    large the configured reset value is."""
    if settings.season_reset_mode == RESET_MODE_FIXED:
        new_points = points - settings.season_reset_value
    else:
        new_points = points - round(points * settings.season_reset_value / 100)
    return max(0, new_points)


def end_season(db: Session, season: Season, at: datetime | None = None) -> None:
    """The one moment a season's result becomes permanent history and
    every user's current points get reset for the next one -- reached both
    by an admin ending a season by hand and by its own scheduled end
    arriving (see sync_season_states), never by two implementations.
    Freezes EVERY user's points/rank into SeasonHistory (even users with 0
    points, for a complete record) before touching a single
    UserRating.total_points, so a crash partway through never leaves a
    user's history missing while their points are already reset -- both
    happen in the same transaction, committed once at the end.

    `at` is the moment recorded as this season's real end; it defaults to
    now, and the scheduler passes the season's own `ends_at` so a backend
    that was down over that moment still records when the season actually
    ended rather than when it was noticed."""
    if season.status == SEASON_COMPLETED:
        raise ValueError("Сезон уже завершён")
    ended_at = at or utc_now()

    settings = get_rating_settings(db)
    user_ids = [row[0] for row in db.query(User.id).all()]

    for user_id in user_ids:
        rating = get_or_create_user_rating(db, user_id)
        rank = current_rank_for_points(db, rating.total_points)
        db.add(
            SeasonHistory(
                user_id=user_id,
                season_id=season.id,
                points=rating.total_points,
                rank_id=rank.id if rank else None,
            )
        )
        rating.total_points = apply_season_reset(rating.total_points, settings)

    season.status = SEASON_COMPLETED
    season.ended_at = ended_at
    db.commit()
