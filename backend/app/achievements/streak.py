"""Records that a user really studied today -- the one source of
truth `streak_days` (see conditions.py's streak_days_count) is computed
from. Called from a small set of already-existing endpoints that fire on
real user activity (opening the dictionary list, answering a lesson
exercise, fetching available phrases for Practice/"Мои фразы") rather than
a new "ping" endpoint Flutter would have to call explicitly on top of
what it already does.
"""

from datetime import date, timedelta

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.achievements.service import check_and_grant_achievements
from app.core.dates import dushanbe_today
from app.models.achievement import UserActivityDay, UserStreakFreeze
from app.models.user import User


# A break of this many days (or more) earns a welcome-back bonus.
COMEBACK_DAYS = 3


def record_activity(db: Session, user: User) -> bool:
    """Idempotent per (user, day): a second call the same day does
    nothing (UserActivityDay has a unique constraint on user_id +
    activity_date). Only re-checks streak achievements the FIRST time
    today is recorded, since that's the only moment the streak count
    could have changed."""
    today = dushanbe_today()
    exists = (
        db.query(UserActivityDay)
        .filter(UserActivityDay.user_id == user.id, UserActivityDay.activity_date == today)
        .first()
        is not None
    )
    if exists:
        return False
    previous = (
        db.query(func.max(UserActivityDay.activity_date))
        .filter(UserActivityDay.user_id == user.id, UserActivityDay.activity_date < today)
        .scalar()
    )
    db.add(UserActivityDay(user_id=user.id, activity_date=today))
    db.flush()  # this session's autoflush is off -- streak_days_count below must see today's own row
    apply_freezes(db, user, today)
    check_and_grant_achievements(db, user, "streak_days")

    from app.seasonpass import award_xp  # season XP: a lit streak day

    award_xp(db, user, "streak", f"streak:{today.isoformat()}")
    if previous is not None and (today - previous).days >= COMEBACK_DAYS:
        award_xp(db, user, "comeback", f"comeback:{today.isoformat()}")

    from app.notifications.reminders import congratulate_streak  # app.notifications imports this package

    congratulate_streak(db, user)
    return True


def active_today(db: Session, user: User) -> bool:
    """Whether today's streak day is already lit (the 🔥 is bright)."""
    return (
        db.query(UserActivityDay.id)
        .filter(UserActivityDay.user_id == user.id, UserActivityDay.activity_date == dushanbe_today())
        .first()
        is not None
    )


def missed_days_needing_freezes(active: set[date], covered: set[date], today: date) -> list[date]:
    """The missed days between the last day before `today` the person was
    active and today that the weekly forgiveness would NOT cover -- the days
    that would break the streak, so each needs a freeze. Walks back from
    yesterday exactly as conditions.streak_with_freezes does."""
    before = [d for d in active if d < today]
    if not before:
        return []
    last = max(before)
    needed: list[date] = []
    used_weeks: set = set()
    pending = None
    day = today - timedelta(days=1)
    while day > last:
        if day in covered:
            pass
        else:
            week = day.isocalendar()[:2]
            if pending is not None or week in used_weeks:
                needed.append(day)
            else:
                used_weeks.add(week)
                pending = day
        day -= timedelta(days=1)
    return needed


def apply_freezes(db: Session, user: User, today: date) -> int:
    """The person is back after a gap: spends streak freezes on the missed
    days the weekly forgiveness does not cover, so the streak survives.
    Spends none unless the stock covers every such day (a streak that
    breaks anyway must not eat freezes). Returns how many were spent. Does
    not commit."""
    if (user.streak_freezes or 0) <= 0:
        return 0
    active = {
        r[0] for r in db.query(UserActivityDay.activity_date).filter(UserActivityDay.user_id == user.id).all()
    }
    covered = {
        r[0] for r in db.query(UserStreakFreeze.covered_date).filter(UserStreakFreeze.user_id == user.id).all()
    }
    needed = missed_days_needing_freezes(active, covered, today)
    if not needed or len(needed) > user.streak_freezes:
        return 0
    for day in needed:
        db.add(UserStreakFreeze(user_id=user.id, covered_date=day))
    user.streak_freezes -= len(needed)
    db.flush()
    _notify_saved(db, user, len(needed), today)
    return len(needed)


_SAVED = {
    "ru": ("Заморозка спасла серию", "Серия сохранена: потрачено заморозок — {n}. Осталось: {left}."),
    "tg": ("Яхкунӣ силсиларо наҷот дод", "Силсила нигоҳ дошта шуд: яхкуниҳои сарфшуда — {n}. Боқӣ: {left}."),
    "uz": ("Muzlatish seriyani saqladi", "Seriya saqlandi: sarflangan muzlatishlar — {n} ta. Qoldi: {left} ta."),
    "en": ("A freeze saved your streak", "Your streak is safe: freezes used — {n}. Left: {left}."),
}


def _notify_saved(db: Session, user: User, spent: int, today: date) -> None:
    try:
        from app.notifications import send_notification

        lang = user.ui_language if user.ui_language in _SAVED else "ru"
        title, body = _SAVED[lang]
        send_notification(
            db, user, body.format(n=spent, left=user.streak_freezes), title=title, dedupe_key=f"freeze:{today.isoformat()}"
        )
    except Exception:  # the message is a courtesy: never lose the streak over it
        pass
