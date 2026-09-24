"""Seasonal rating: a system entirely separate from Achievements (see
app/models/achievement.py) -- different tables, different triggers,
different admin section, never cross-referenced. The two happen to react
to some of the same underlying events (a word becoming learned), but nothing
here reads or writes an Achievement/UserAchievement row, and nothing there
reads or writes any table below.
"""

from datetime import datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base

RESET_MODE_FIXED = "fixed"
RESET_MODE_PERCENT = "percent"

# A season that exists and has a period, but whose start moment hasn't
# arrived yet -- the status that makes "create several seasons in advance"
# possible without ever having two live ones.
SEASON_SCHEDULED = "scheduled"
SEASON_ACTIVE = "active"
SEASON_COMPLETED = "completed"


class RatingSettings(Base):
    """A single-row table (always id=1), the same "one admin-configured
    global value" idiom as LearningSettings -- holds the two numbers that
    control rating end to end: how many points a newly-learned word is
    worth right now, and how the seasonal reset behaves. Exactly one reset
    mode is ever active (a plain string column, not two competing flags),
    so there is never a state where both a fixed and a percent reset could
    apply at once."""

    __tablename__ = "rating_settings"

    id: Mapped[int] = mapped_column(primary_key=True)
    points_per_learned_word: Mapped[int] = mapped_column(Integer, nullable=False, default=10, server_default="10")
    season_reset_mode: Mapped[str] = mapped_column(
        String(16), nullable=False, default=RESET_MODE_FIXED, server_default=RESET_MODE_FIXED
    )
    # Interpreted as a point count when season_reset_mode == "fixed", or a
    # 0-100 percentage when "percent" -- never both at once.
    season_reset_value: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Rank(Base):
    """One rank DEFINITION an admin created (Bronze, Silver, ...) -- a
    points range plus display info. Never hardcoded in Flutter or in any
    backend condition/if-branch: app/rating/service.py's
    `current_rank_for_points` picks the matching enabled Rank purely by
    comparing `total_points` against `min_points`/`max_points`, the same
    "definition row, no per-item branching" shape as Achievement.

    `max_points=None` means no upper bound (the top rank). `icon_key` is an
    admin-uploaded image (same storage-key convention as
    Achievement.icon_key/Word.image_key), never emoji -- and may be null,
    in which case the UI falls back to a generic badge rather than
    breaking."""

    __tablename__ = "ranks"
    __table_args__ = (
        CheckConstraint("max_points IS NULL OR max_points >= min_points", name="ck_rank_range_valid"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    min_points: Mapped[int] = mapped_column(Integer, nullable=False)
    max_points: Mapped[int | None] = mapped_column(Integer, nullable=True)
    icon_key: Mapped[str | None] = mapped_column(String(500), nullable=True)
    color: Mapped[str] = mapped_column(String(9), nullable=False, default="#6366F1", server_default="#6366F1")
    order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Season(Base):
    """One rating season, with its own id, its own period and its own
    status -- any number of them may exist at once, but at most ONE may be
    `status="active"`, which the partial unique index below enforces at the
    database level (the same idiom Lesson uses for its own "at most one
    incomplete" rule) rather than relying on router code alone.

    The three statuses are a lifecycle, never set by hand from two
    different places: a season is created `"scheduled"`, becomes
    `"active"` when `starts_at` arrives, and becomes `"completed"` either
    when `ends_at` arrives or when an admin ends it early. The single
    function that makes every one of those transitions is
    app/rating/service.py's `sync_season_states` -- so the state after a
    backend restart is decided by the stored period, not by whatever
    happened to be in memory.

    Two moments, deliberately separate:
      - `ends_at` is the PLANNED end an admin scheduled. Null means "ends
        only when an admin says so" -- and blocks scheduling anything
        after it, since nothing can know when it frees up.
      - `ended_at` is when the season ACTUALLY ended, written once by
        `end_season`. Null until then.

    Ending a season is the one moment SeasonHistory rows get written and
    every user's UserRating.total_points gets reset; a completed Season
    row itself is never edited afterwards, only ever read."""

    __tablename__ = "seasons"
    __table_args__ = (
        Index(
            "uq_single_active_season",
            "status",
            unique=True,
            postgresql_where=text("status = 'active'"),
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ends_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, default=SEASON_SCHEDULED, server_default=SEASON_SCHEDULED
    )
    # An admin-uploaded picture for the season, same storage-key convention
    # as Rank.icon_key. Stored only for now -- nothing renders it yet.
    icon_key: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class UserRating(Base):
    """The user's CURRENT rating points -- the one row app/rating/service.py
    ever writes `total_points` to, and the one row a user's current rank is
    ever computed from (never stored as an independent value that could
    drift from `total_points` -- see current_rank_for_points). One row per
    user, created lazily on that user's first awarded word."""

    __tablename__ = "user_ratings"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True, index=True
    )
    total_points: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class UserWordPoints(Base):
    """Proof a specific user was already awarded points for a specific
    Word -- the one thing that guarantees "one word grants rating points
    to a user at most once", exactly mirroring UserAchievement's own
    (user_id, achievement_id) uniqueness role. `points_awarded` is a
    SNAPSHOT of RatingSettings.points_per_learned_word at the moment this
    word was learned -- a later admin change to that setting must never
    rewrite what this row already recorded."""

    __tablename__ = "user_word_points"
    __table_args__ = (UniqueConstraint("user_id", "word_id", name="uq_user_word_points_once"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    word_id: Mapped[int] = mapped_column(ForeignKey("words.id", ondelete="CASCADE"), nullable=False, index=True)
    points_awarded: Mapped[int] = mapped_column(Integer, nullable=False)
    awarded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class SeasonHistory(Base):
    """One user's frozen result for one COMPLETED season -- their points
    and rank at the exact moment that season ended, captured once and
    never overwritten by later seasons' resets. This is deliberately a
    separate row from UserRating/Season for the same reason UserAchievement
    is separate from Achievement: a season reset (or a later Rank edit)
    must never rewrite what a user already achieved in a past season."""

    __tablename__ = "season_history"
    __table_args__ = (UniqueConstraint("user_id", "season_id", name="uq_season_history_once"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    season_id: Mapped[int] = mapped_column(ForeignKey("seasons.id", ondelete="CASCADE"), nullable=False, index=True)
    points: Mapped[int] = mapped_column(Integer, nullable=False)
    rank_id: Mapped[int | None] = mapped_column(ForeignKey("ranks.id", ondelete="RESTRICT"), nullable=True)
    ended_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    season: Mapped["Season"] = relationship()
    rank: Mapped["Rank | None"] = relationship()
