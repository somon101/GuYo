"""Notifications: one inbox per user.

Deliberately ONE kind of row for every notification, however it came to
exist. An admin writing a message by hand and a future rule firing on an
event both produce the same Notification -- they differ only in the
`source` that stamped it and the `dedupe_key` that keeps an automatic
sender from repeating itself. Nothing downstream (the user's inbox, the
unread count, marking read) needs to know which it was.

That is the same shape app/achievements/ already uses: definitions live
apart, one idempotent service function does the granting, and event sites
call it defensively. See app/notifications/service.py -- adding an
automatic trigger later means calling that function from an event site,
not reshaping this table.
"""

from datetime import datetime

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

# Where a notification came from. A plain string rather than an enum so a
# future trigger can introduce its own source without a schema migration;
# the only one that exists today is the admin writing a message by hand.
SOURCE_MANUAL = "manual"


class Notification(Base):
    """One message in one user's inbox.

    `source` is provenance, not behaviour -- "manual" today, and a future
    rule would stamp its own key ("inactivity", "rank_drop", ...). Reading
    and displaying a notification never branches on it; it exists so an
    admin can see WHY something was sent, and so a future trigger can find
    its own past sends.

    `dedupe_key` is what makes automatic sending safe to call defensively,
    the way check_and_grant_achievements already is: a rule passes a key
    describing exactly what it is reporting ("inactive:2026-09-24"), and
    UNIQUE(user_id, dedupe_key) guarantees at the database level that the
    same thing is never sent to the same person twice. Manual messages
    leave it NULL -- Postgres allows any number of NULLs under a unique
    constraint, so an admin can send the same text as often as they like.

    `read_at` doubles as the read flag and the record of when: a separate
    boolean would only be able to disagree with it.
    """

    __tablename__ = "notifications"
    __table_args__ = (UniqueConstraint("user_id", "dedupe_key", name="uq_notification_dedupe_key"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    source: Mapped[str] = mapped_column(
        String(64), nullable=False, default=SOURCE_MANUAL, server_default=SOURCE_MANUAL
    )
    # Optional: a short headline above the body. Manual messages often
    # don't need one, so the client renders the body alone when it is null.
    title: Mapped[str | None] = mapped_column(String(120), nullable=True)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    dedupe_key: Mapped[str | None] = mapped_column(String(200), nullable=True)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True)


class PushToken(Base):
    """One phone that can receive push notifications for a user -- the FCM
    registration token the app reports after login. A token belongs to one
    device, so it is unique: when a different account logs in on the same
    phone, the row moves to that account instead of duplicating."""

    __tablename__ = "push_tokens"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    token: Mapped[str] = mapped_column(String(512), nullable=False, unique=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


# ReminderRule.kind values. `days` means something different for each:
REMINDER_INACTIVITY = "inactivity"  # sent after exactly `days` whole days without opening the app
REMINDER_STREAK_RISK = "streak_risk"  # evening warning; `days` = the shortest streak worth warning about
REMINDER_STREAK_MILESTONE = "streak_milestone"  # congratulation on the day the streak reaches `days`
REMINDER_KINDS = (REMINDER_INACTIVITY, REMINDER_STREAK_RISK, REMINDER_STREAK_MILESTONE)


class ReminderRule(Base):
    """One automatic message an admin wrote in Admin Web. Several enabled
    rules with the same (kind, days) are variants of one reminder: a user
    gets one of them at random, never all. `{дни}` / `{дни+1}` in the text
    are replaced with the user's streak length. See
    app/notifications/reminders.py for when each kind is sent."""

    __tablename__ = "reminder_rules"
    __table_args__ = (CheckConstraint("days >= 1", name="ck_reminder_rule_days_positive"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    kind: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    days: Mapped[int] = mapped_column(Integer, nullable=False)
    title: Mapped[str | None] = mapped_column(String(120), nullable=True)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class ReminderSettings(Base):
    """Single row (id=1). Hours are Asia/Dushanbe wall-clock hours."""

    __tablename__ = "reminder_settings"

    id: Mapped[int] = mapped_column(primary_key=True)
    # When the "streak at risk" warning goes out.
    streak_risk_hour: Mapped[int] = mapped_column(Integer, nullable=False, default=20, server_default="20")
    # Inactivity reminders go out at the hour the user usually studies; this
    # is the fallback for someone with no answers in the last 30 days.
    default_hour: Mapped[int] = mapped_column(Integer, nullable=False, default=18, server_default="18")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
