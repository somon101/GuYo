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

from sqlalchemy import DateTime, ForeignKey, String, Text, UniqueConstraint, func
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
