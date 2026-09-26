"""The one place Premium is decided: who has it, until when, and what a
user may still do today and this week.

Everything that gates on Premium goes through here -- the lesson endpoint
asks check_lesson_quota, the automatic features ask
automatic_feature_allowed -- so there is only ever one definition of
"is this user Premium right now".
"""

from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.dates import DUSHANBE_TZ, dushanbe_day_start, dushanbe_today, dushanbe_week_start, utc_now
from app.models.admin import Admin
from app.models.lesson import Lesson
from app.models.premium import GRANT_SOURCE_ADMIN, PremiumGrant, PremiumSettings
from app.models.user import User

# The notification a user gets when Premium is granted -- its own source,
# so Admin Web's notifications list shows why it was sent.
NOTIFICATION_SOURCE_PREMIUM = "premium"

FEATURE_ADAPTIVE_LESSONS = "adaptive_lessons"
FEATURE_PERSONAL_QUESTS = "personal_quests"


def get_premium_settings(db: Session) -> PremiumSettings:
    """Same "single row, always id=1" idiom as get_rating_settings --
    created lazily with its defaults (3 a day, 10 a week for free users,
    no limit for Premium) on first read."""
    settings = db.get(PremiumSettings, 1)
    if settings is None:
        settings = PremiumSettings(id=1)
        db.add(settings)
        db.flush()
    return settings


def _live_grants(db: Session, user_id: int, now: datetime):
    return db.query(PremiumGrant).filter(
        PremiumGrant.user_id == user_id,
        PremiumGrant.revoked_at.is_(None),
        PremiumGrant.ends_at > now,
    )


def premium_until(db: Session, user: User, *, now: datetime | None = None) -> datetime | None:
    """When this user's Premium ends, or None if they don't have it right
    now. Grants are only ever chained end-to-start (see grant_premium), so
    while one covers "now" the latest end among them is the real end."""
    now = now or utc_now()
    live = _live_grants(db, user.id, now)
    if live.filter(PremiumGrant.starts_at <= now).first() is None:
        return None
    return live.with_entities(func.max(PremiumGrant.ends_at)).scalar()


def is_premium(db: Session, user: User, *, now: datetime | None = None) -> bool:
    return premium_until(db, user, now=now) is not None


def grant_premium(
    db: Session,
    user: User,
    days: int,
    *,
    note: str | None = None,
    admin: Admin | None = None,
    source: str = GRANT_SOURCE_ADMIN,
) -> PremiumGrant:
    """Adds `days` of Premium. If the user already has it, the new period
    starts where the current one ends -- paying again while subscribed
    extends, never overlaps and wastes days.

    Also tells the user, through the same send_notification every other
    message goes through. Does NOT commit: the caller owns the
    transaction."""
    from app.notifications import send_notification  # app.notifications has no reason to load this module first

    if days <= 0:
        raise ValueError("Срок должен быть больше нуля")

    now = utc_now()
    current_end = premium_until(db, user, now=now)
    starts_at = current_end or now
    grant = PremiumGrant(
        user_id=user.id,
        starts_at=starts_at,
        ends_at=starts_at + timedelta(days=days),
        days=days,
        source=source,
        note=(note.strip() or None) if note else None,
        granted_by_admin_id=admin.id if admin is not None else None,
    )
    db.add(grant)
    db.flush()

    until = grant.ends_at.astimezone(DUSHANBE_TZ).strftime("%d.%m.%Y")
    send_notification(
        db,
        user,
        f"Спасибо за поддержку! GuYo Premium активен до {until}.",
        title="GuYo Premium",
        source=NOTIFICATION_SOURCE_PREMIUM,
    )
    return grant


def revoke_premium(db: Session, user: User) -> int:
    """Ends this user's Premium immediately: every grant still running or
    still to come is marked revoked (kept, not deleted, so the history of
    what was paid stays). Returns how many grants were affected. Does NOT
    commit."""
    now = utc_now()
    grants = _live_grants(db, user.id, now).all()
    for grant in grants:
        grant.revoked_at = now
    return len(grants)


def automatic_feature_allowed(db: Session, user: User, feature: str) -> bool:
    """Whether an automatic feature (adaptive lessons, personal quests)
    may run for this user -- always, or only with Premium, as the admin
    set it in PremiumSettings."""
    settings = get_premium_settings(db)
    premium_only = {
        FEATURE_ADAPTIVE_LESSONS: settings.adaptive_lessons_premium_only,
        FEATURE_PERSONAL_QUESTS: settings.personal_quests_premium_only,
    }[feature]
    return not premium_only or is_premium(db, user)


@dataclass
class LessonQuota:
    """Where a user stands against the lesson limits right now. A limit of
    None means unlimited. Only lessons the user created themselves are
    counted -- adaptive ones never are."""

    is_premium: bool
    premium_until: datetime | None
    daily_limit: int | None
    daily_used: int
    weekly_limit: int | None
    weekly_used: int
    next_day_starts_at: datetime
    next_week_starts_at: datetime

    @property
    def remaining(self) -> int | None:
        """How many more lessons can be created right now -- the tighter of
        the two limits -- or None if neither applies."""
        left = [
            max(0, limit - used)
            for limit, used in ((self.daily_limit, self.daily_used), (self.weekly_limit, self.weekly_used))
            if limit is not None
        ]
        return min(left) if left else None

    @property
    def blocked_by(self) -> str | None:
        """"week" or "day" when no lesson can be created now -- the week
        first, since waiting for tomorrow would not help -- else None."""
        if self.weekly_limit is not None and self.weekly_used >= self.weekly_limit:
            return "week"
        if self.daily_limit is not None and self.daily_used >= self.daily_limit:
            return "day"
        return None

    @property
    def resets_at(self) -> datetime | None:
        """When creating becomes possible again, if it is blocked now."""
        return {"week": self.next_week_starts_at, "day": self.next_day_starts_at}.get(self.blocked_by)


def lesson_quota(db: Session, user: User) -> LessonQuota:
    settings = get_premium_settings(db)
    until = premium_until(db, user)
    premium = until is not None
    today = dushanbe_today()
    day_start = dushanbe_day_start(today)
    week_start = dushanbe_week_start(today)

    def created_since(start: datetime) -> int:
        return (
            db.query(func.count(Lesson.id))
            .filter(Lesson.user_id == user.id, Lesson.is_adaptive.is_(False), Lesson.created_at >= start)
            .scalar()
            or 0
        )

    return LessonQuota(
        is_premium=premium,
        premium_until=until,
        daily_limit=settings.premium_daily_lesson_limit if premium else settings.free_daily_lesson_limit,
        daily_used=created_since(day_start),
        weekly_limit=settings.premium_weekly_lesson_limit if premium else settings.free_weekly_lesson_limit,
        weekly_used=created_since(week_start),
        next_day_starts_at=dushanbe_day_start(today + timedelta(days=1)),
        next_week_starts_at=week_start + timedelta(days=7),
    )


class LessonLimitReached(Exception):
    """Raised by check_lesson_quota; its message is shown to the user as
    is."""


def check_lesson_quota(db: Session, user: User) -> LessonQuota:
    """Raises LessonLimitReached if this user may not create another
    lesson right now. Two requests at the very same moment in different
    dictionaries could both pass and overshoot by one -- an accepted edge,
    not worth a lock for a daily allowance."""
    quota = lesson_quota(db, user)
    blocked = quota.blocked_by
    if blocked is None:
        return quota

    if blocked == "week":
        message = (
            f"Лимит уроков на эту неделю исчерпан: {quota.weekly_used} из {quota.weekly_limit}. "
            "Новые уроки можно будет создать с понедельника."
        )
    else:
        message = (
            f"Лимит уроков на сегодня исчерпан: {quota.daily_used} из {quota.daily_limit}. "
            "Новые уроки можно будет создать завтра."
        )
    if not quota.is_premium:
        message += " С GuYo Premium — без ограничений."
    raise LessonLimitReached(message)
