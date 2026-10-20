"""Weekly learning numbers: the weekly recap message and the "Мой путь" screen."""

from datetime import date, datetime, timedelta

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.dates import DUSHANBE_TZ, dushanbe_today
from app.models.achievement import UserActivityDay
from app.models.word_progress import WordProgress


def week_start(day: date) -> date:
    """The Monday of the week `day` falls in."""
    return day - timedelta(days=day.weekday())


def _bounds(monday: date) -> tuple[datetime, datetime]:
    start = datetime.combine(monday, datetime.min.time(), tzinfo=DUSHANBE_TZ)
    return start, start + timedelta(days=7)


def week_numbers(db: Session, user_id: int, monday: date) -> dict:
    start, end = _bounds(monday)
    words = (
        db.query(func.count(WordProgress.id))
        .filter(WordProgress.user_id == user_id, WordProgress.mastered_at >= start, WordProgress.mastered_at < end)
        .scalar()
        or 0
    )
    days = (
        db.query(func.count(UserActivityDay.id))
        .filter(
            UserActivityDay.user_id == user_id,
            UserActivityDay.activity_date >= monday,
            UserActivityDay.activity_date < monday + timedelta(days=7),
        )
        .scalar()
        or 0
    )
    return {"week_start": monday, "words": int(words), "active_days": int(days)}


def weekly_series(db: Session, user_id: int, weeks: int = 12) -> list[dict]:
    """Oldest first, ending with the current week."""
    this_monday = week_start(dushanbe_today())
    return [week_numbers(db, user_id, this_monday - timedelta(weeks=n)) for n in range(weeks - 1, -1, -1)]


def total_learned(db: Session, user_id: int) -> int:
    return (
        db.query(func.count(WordProgress.id))
        .filter(WordProgress.user_id == user_id, WordProgress.mastered_at.isnot(None))
        .scalar()
        or 0
    )


def total_active_days(db: Session, user_id: int) -> int:
    return db.query(func.count(UserActivityDay.id)).filter(UserActivityDay.user_id == user_id).scalar() or 0
