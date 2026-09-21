"""Records that a user did SOMETHING in the app today -- the one source of
truth `streak_days` (see conditions.py's streak_days_count) is computed
from. Called from a small set of already-existing endpoints that fire on
real user activity (opening the dictionary list, answering a lesson
exercise, fetching available phrases for Practice/"Мои фразы") rather than
a new "ping" endpoint Flutter would have to call explicitly on top of
what it already does.
"""

from datetime import date

from sqlalchemy.orm import Session

from app.achievements.service import check_and_grant_achievements
from app.models.achievement import UserActivityDay
from app.models.user import User


def record_activity(db: Session, user: User) -> None:
    """Idempotent per (user, day): a second call the same day does
    nothing (UserActivityDay has a unique constraint on user_id +
    activity_date). Only re-checks streak achievements the FIRST time
    today is recorded, since that's the only moment the streak count
    could have changed."""
    today = date.today()
    exists = (
        db.query(UserActivityDay)
        .filter(UserActivityDay.user_id == user.id, UserActivityDay.activity_date == today)
        .first()
        is not None
    )
    if exists:
        return
    db.add(UserActivityDay(user_id=user.id, activity_date=today))
    db.flush()  # this session's autoflush is off -- streak_days_count below must see today's own row
    check_and_grant_achievements(db, user, "streak_days")
