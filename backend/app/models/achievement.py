from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Achievement(Base):
    """One achievement DEFINITION an admin created in Admin Web -- e.g.
    "Первый шаг: открой первую фразу". This is deliberately a separate
    entity from whether/when any given user actually earned it (see
    UserAchievement below): editing this row's title/description/icon
    later must never look like a new medal to a user who already has it,
    since UserAchievement only ever stores a reference to this row's `id`.

    `condition_type` + `condition_value` describe HOW this achievement is
    earned, in a form the backend can evaluate generically (see
    app/achievements/ -- one module per condition_type) rather than one
    hardcoded if-branch per achievement. Only "phrases_opened" exists
    today (reusing the exact same "Мои фразы" availability logic, see
    app/achievements/conditions.py), but the shape supports any future
    numeric, ever-increasing measure (words learned, lessons completed,
    ...) without a schema change -- just a new condition_type string and
    a new module registering itself in CONDITION_TYPES.

    `order` is a plain admin-set integer (e.g. 10, 20, 30) controlling
    display order -- never inferred from id/condition_value, since an
    admin may want a different narrative order than either of those."""

    __tablename__ = "achievements"

    id: Mapped[int] = mapped_column(primary_key=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str] = mapped_column(String(500), nullable=False)
    # A fixed identifier from an admin-facing icon catalog (see
    # app/achievements/icons.py) -- never free-text HTML/SVG. The client
    # maps this id to its own icon asset.
    icon: Mapped[str] = mapped_column(String(64), nullable=False)
    condition_type: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    condition_value: Mapped[int] = mapped_column(Integer, nullable=False)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class UserAchievement(Base):
    """The GRANT record: proof a specific user met a specific Achievement's
    condition, and when. Deliberately a separate table/row from Achievement
    itself (never a boolean flag on Achievement, never a copy of its
    title/icon) -- so editing or even deleting the Achievement definition
    later can never retroactively rewrite history, and a user's earned
    badge is never confused with the badge's own (mutable) definition.

    The unique constraint is what actually guarantees "one achievement is
    granted at most once per user" at the database level, not just as an
    application-level convention that a race condition could violate."""

    __tablename__ = "user_achievements"
    __table_args__ = (UniqueConstraint("user_id", "achievement_id", name="uq_user_achievement_once"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    achievement_id: Mapped[int] = mapped_column(
        ForeignKey("achievements.id", ondelete="CASCADE"), nullable=False, index=True
    )
    earned_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    achievement: Mapped["Achievement"] = relationship()
