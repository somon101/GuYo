"""GuYo Premium: paid access, granted by hand.

Payment happens outside the app -- the user transfers money, the admin
finds them by their 9-digit account number in Admin Web and grants a
period. Nothing here talks to a payment provider, and nothing needs to for
an automatic channel (Google Play, a local wallet) to be added later: it
would be one more caller of app/premium/service.py's grant_premium,
stamping its own `source`, exactly like a future automatic notification
is one more caller of send_notification.

Premium is never a stored flag. A user has it while at least one
non-revoked PremiumGrant covers "now" -- so it ends on its own the moment
the last period runs out, with no scheduler to forget and no flag that can
disagree with the periods it was derived from.
"""

from datetime import datetime

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

# Where a grant came from. A plain string, same reasoning as
# Notification.source: a future payment channel adds its own value
# without a schema migration. Only the admin granting by hand exists today.
GRANT_SOURCE_ADMIN = "admin"


class PremiumSettings(Base):
    """Single-row table (always id=1), same idiom as RatingSettings/
    PrioritySettings -- created lazily with defaults on first read.

    Lesson limits: NULL means "no limit". Only lessons a user creates
    themselves count -- an adaptive lesson the system builds is never
    counted against anyone. Days and weeks are Asia/Dushanbe calendar
    days/weeks (Monday start), the same day boundary quests reset on.

    The two *_premium_only switches decide whether the automatic features
    (adaptive lessons, personal quests) run for everyone or only for
    Premium users -- switchable here so changing that decision never
    needs a code change.

    `price_text` and `payment_instructions` are what the app's Premium
    screen shows verbatim: the admin writes where to send money and how
    much, so changing a card number never needs a new app build."""

    __tablename__ = "premium_settings"
    __table_args__ = (
        CheckConstraint("free_daily_lesson_limit IS NULL OR free_daily_lesson_limit >= 0", name="ck_premium_free_daily"),
        CheckConstraint("free_weekly_lesson_limit IS NULL OR free_weekly_lesson_limit >= 0", name="ck_premium_free_weekly"),
        CheckConstraint(
            "premium_daily_lesson_limit IS NULL OR premium_daily_lesson_limit >= 0", name="ck_premium_premium_daily"
        ),
        CheckConstraint(
            "premium_weekly_lesson_limit IS NULL OR premium_weekly_lesson_limit >= 0", name="ck_premium_premium_weekly"
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)

    free_daily_lesson_limit: Mapped[int | None] = mapped_column(Integer, nullable=True, default=3, server_default="3")
    free_weekly_lesson_limit: Mapped[int | None] = mapped_column(Integer, nullable=True, default=10, server_default="10")
    premium_daily_lesson_limit: Mapped[int | None] = mapped_column(Integer, nullable=True, default=None)
    premium_weekly_lesson_limit: Mapped[int | None] = mapped_column(Integer, nullable=True, default=None)

    adaptive_lessons_premium_only: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    personal_quests_premium_only: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )

    price_text: Mapped[str] = mapped_column(String(200), nullable=False, default="", server_default="")
    payment_instructions: Mapped[str] = mapped_column(Text, nullable=False, default="", server_default="")

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class PremiumGrant(Base):
    """One paid period for one user: [starts_at, ends_at).

    Kept as history rather than overwritten, so Admin Web can show who
    paid when and for how long, with the admin's own note ("Алиф, 50
    сомони"). Extending an active subscription adds a new grant that
    starts where the current one ends -- see grant_premium.

    `revoked_at` switches a grant off early without deleting the record of
    it; a revoked grant never counts towards Premium again."""

    __tablename__ = "premium_grants"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ends_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    days: Mapped[int] = mapped_column(Integer, nullable=False)
    source: Mapped[str] = mapped_column(
        String(64), nullable=False, default=GRANT_SOURCE_ADMIN, server_default=GRANT_SOURCE_ADMIN
    )
    note: Mapped[str | None] = mapped_column(String(500), nullable=True)
    granted_by_admin_id: Mapped[int | None] = mapped_column(
        ForeignKey("admins.id", ondelete="SET NULL"), nullable=True
    )
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
