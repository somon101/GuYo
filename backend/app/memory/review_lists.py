"""«Повторить сегодня» as fixed lists.

The memory model keeps watching every learned word; once at least N of
them (N = the admin's «Повтори слово» number) are being forgotten and are
not already waiting in a list, those N -- the most forgotten first -- are
frozen into a list together with the reason for each (its numbers right
now). Ordinary lessons and quests never change a list: only a right
answer while reviewing ticks a word off, a wrong one leaves it there. A
list closes when every word is ticked; then the next one in the queue
becomes active -- after the admin's pause -- (and gets its own push, app/priority/background_prep.py).
At most MAX_OPEN_LISTS lists are open (active + queued) at a time."""

from datetime import timedelta

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.dates import utc_now
from app.models.review_list import (
    STATUS_ACTIVE,
    STATUS_CLOSED,
    STATUS_QUEUED,
    ReviewList,
    ReviewListWord,
)

MAX_OPEN_LISTS = 3


def list_size(db: Session) -> int:
    from app.notifications.reminders import get_reminder_settings

    return max(1, get_reminder_settings(db).review_push_min_words)


def _open_lists(db: Session, user_id: int, dictionary_id: int) -> list[ReviewList]:
    return (
        db.query(ReviewList)
        .filter(
            ReviewList.user_id == user_id,
            ReviewList.dictionary_id == dictionary_id,
            ReviewList.status != STATUS_CLOSED,
        )
        .order_by(ReviewList.id)
        .all()
    )


def pause_hours(db: Session) -> int:
    from app.notifications.reminders import get_reminder_settings

    return max(0, get_reminder_settings(db).review_list_pause_hours)


def _pause_over(db: Session, user_id: int, dictionary_id: int) -> bool:
    """Whether enough time has passed since the user's last list was closed
    for the next one to open (the admin's «пауза между списками»)."""
    hours = pause_hours(db)
    if hours <= 0:
        return True
    last_closed = (
        db.query(func.max(ReviewList.closed_at))
        .filter(
            ReviewList.user_id == user_id,
            ReviewList.dictionary_id == dictionary_id,
            ReviewList.status == STATUS_CLOSED,
        )
        .scalar()
    )
    return last_closed is None or utc_now() >= last_closed + timedelta(hours=hours)


def _activate_next(db: Session, lists: list[ReviewList]) -> ReviewList | None:
    """Makes sure one open list is active: the oldest queued one if none is,
    once the pause after the previously closed list is over."""
    active = next((rl for rl in lists if rl.status == STATUS_ACTIVE), None)
    if active is None:
        queued = next((rl for rl in lists if rl.status == STATUS_QUEUED), None)
        if queued is not None and _pause_over(db, queued.user_id, queued.dictionary_id):
            queued.status = STATUS_ACTIVE
            queued.activated_at = utc_now()
            queued.notified_at = None
            active = queued
    return active


def refresh_lists(db: Session, user_id: int, dictionary_id: int) -> ReviewList | None:
    """Freezes new lists while there are enough forgotten words and room in
    the queue; returns the active list (None when there is nothing to
    review). Does not commit."""
    from app.memory.service import due_progress_rows
    from app.priority.settings import get_priority_settings

    lists = _open_lists(db, user_id, dictionary_id)
    settings = get_priority_settings(db)
    if len(lists) < MAX_OPEN_LISTS:
        size = list_size(db)
        taken = set()
        if lists:
            taken = {
                w for (w,) in db.query(ReviewListWord.word_id).filter(ReviewListWord.list_id.in_([rl.id for rl in lists]))
            }
        candidates = [(r, p) for r, p in due_progress_rows(db, user_id, dictionary_id) if p.word_id not in taken]
        now = utc_now()
        while len(candidates) >= size and len(lists) < MAX_OPEN_LISTS:
            chunk, candidates = candidates[:size], candidates[size:]
            rl = ReviewList(user_id=user_id, dictionary_id=dictionary_id, status=STATUS_QUEUED, size=size, created_at=now)
            db.add(rl)
            db.flush()
            for i, (r, p) in enumerate(chunk, start=1):
                db.add(
                    ReviewListWord(
                        list_id=rl.id,
                        word_id=p.word_id,
                        position=i,
                        recall=r,
                        target=settings.memory_target_retention,
                        stability=p.memory_stability,
                        difficulty=p.memory_difficulty,
                        last_review=p.memory_last_review,
                        review_days=p.memory_review_days or 0,
                    )
                )
            lists.append(rl)
    active = _activate_next(db, lists)
    db.flush()
    return active


def active_list(db: Session, user_id: int, dictionary_id: int) -> ReviewList | None:
    return (
        db.query(ReviewList)
        .filter(
            ReviewList.user_id == user_id,
            ReviewList.dictionary_id == dictionary_id,
            ReviewList.status == STATUS_ACTIVE,
        )
        .first()
    )


def remaining_word_ids(db: Session, review_list: ReviewList) -> list[int]:
    return [
        w
        for (w,) in db.query(ReviewListWord.word_id)
        .filter(ReviewListWord.list_id == review_list.id, ReviewListWord.done_at.is_(None))
        .order_by(ReviewListWord.position)
    ]


def pending_entry(db: Session, user_id: int, dictionary_id: int, word_id: int) -> ReviewListWord | None:
    """This word's not-yet-done row in the user's active list, if any."""
    active = active_list(db, user_id, dictionary_id)
    if active is None:
        return None
    return (
        db.query(ReviewListWord)
        .filter(
            ReviewListWord.list_id == active.id,
            ReviewListWord.word_id == word_id,
            ReviewListWord.done_at.is_(None),
        )
        .first()
    )


def record_review_answer(db: Session, entry: ReviewListWord, is_correct: bool) -> None:
    """A review answer on a word of the active list: a right one ticks it
    off; the last tick closes the list and activates the next one. A wrong
    answer changes nothing -- the word stays until it is answered right.
    Does not commit."""
    if not is_correct:
        return
    now = utc_now()
    entry.done_at = now
    db.flush()
    review_list = db.get(ReviewList, entry.list_id)
    from app.models.user import User
    from app.seasonpass import award_xp

    owner = db.get(User, review_list.user_id)
    if owner is not None:
        award_xp(db, owner, "review", f"review:{entry.id}")
    left = (
        db.query(ReviewListWord.id)
        .filter(ReviewListWord.list_id == review_list.id, ReviewListWord.done_at.is_(None))
        .first()
    )
    if left is None:
        review_list.status = STATUS_CLOSED
        review_list.closed_at = now
        db.flush()
        refresh_lists(db, review_list.user_id, review_list.dictionary_id)
