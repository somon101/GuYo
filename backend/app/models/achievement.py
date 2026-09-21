from datetime import date, datetime

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Integer, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base

# Plain strings over a DB enum, same convention as Dictionary.language and
# every exercise_key in this project -- a future value never needs a
# migration.
VISIBILITY_VISIBLE = "visible"
VISIBILITY_HIDDEN = "hidden"


class Achievement(Base):
    """One achievement DEFINITION an admin created in Admin Web -- e.g.
    "Первый шаг: открой первую фразу". Deliberately a separate entity from
    whether/when any given user actually earned it (see UserAchievement
    below): editing this row's title/slogan/icon/color later must never
    look like a new medal to a user who already has it, since
    UserAchievement only ever stores a reference to this row's own `id`.

    `condition_type` + `condition_value` describe HOW this achievement is
    earned, in a form the backend can evaluate generically (see
    app/achievements/ -- one function per condition_type, registered in
    CONDITION_TYPES) rather than one hardcoded if-branch per achievement.
    Adding a future condition_type is one new function there plus one new
    registry entry -- this model never changes shape for it.

    `icon_key` is an admin-uploaded image (same storage-key convention as
    Word.image_key -- see app/core/storage.py), never a free-text emoji/
    HTML/SVG field. `color` is a plain "#RRGGBB" hex string the admin
    picks freely, not tied to condition_type.

    `visibility` + `show_before_unlock` control what an unearned
    achievement looks like to a user who hasn't earned it yet:
    - visible: always shown normally, with real progress.
    - hidden + show_before_unlock=True: shown as a locked "mystery" entry
      (the real icon, dimmed; no title/condition revealed).
    - hidden + show_before_unlock=False: not shown to the user AT ALL
      until they actually earn it.

    `order` is a plain admin-set integer controlling display order --
    never inferred from id/condition_value, so an admin can freely
    rearrange the visual chain (see Admin Web's drag-and-drop)."""

    __tablename__ = "achievements"

    id: Mapped[int] = mapped_column(primary_key=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    # The short reveal text a user sees once they earn it (spec calls this
    # "слоган" -- same field as before, just now documented under that name).
    description: Mapped[str] = mapped_column(String(500), nullable=False)
    icon_key: Mapped[str | None] = mapped_column(String(500), nullable=True)
    color: Mapped[str] = mapped_column(String(9), nullable=False, default="#6366F1", server_default="#6366F1")
    condition_type: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    condition_value: Mapped[int] = mapped_column(Integer, nullable=False)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    visibility: Mapped[str] = mapped_column(
        String(16), nullable=False, default=VISIBILITY_VISIBLE, server_default=VISIBILITY_VISIBLE
    )
    show_before_unlock: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
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


class UserActivityDay(Base):
    """One row = this user did SOMETHING in the app on this calendar date
    (server-side, UTC date -- never the phone's local clock, so streaks
    can't be gamed or corrupted by a device's timezone/clock). Recorded
    idempotently (see app/achievements/streak.py's record_activity) from a
    small set of existing, already-fired endpoints (opening the dictionary
    list, answering a lesson exercise, fetching available phrases) rather
    than a new "ping" endpoint Flutter would need to call explicitly.

    This is the one source of truth "streak_days" (see app/achievements/
    conditions.py) is computed from -- never a separately-maintained
    counter that could drift from what actually happened."""

    __tablename__ = "user_activity_days"
    __table_args__ = (UniqueConstraint("user_id", "activity_date", name="uq_user_activity_day"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    activity_date: Mapped[date] = mapped_column(Date, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
