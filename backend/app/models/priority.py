"""Priority: an analytics layer computed ON TOP of WordProgress/WordLevel/
WordAttempt -- never a second progress system. Nothing here is read by
scoring, levels, achievements or rating; app/priority/ is the only code
that reads these tables, and it never writes to WordProgress/WordLevel's
own score columns either.

Every number an admin can tune lives in one of the four tables below.
None of it is business math decided once and for all -- the seed values
in the migration are explicitly starting examples (see that migration's
own docstring), not a formula anyone signed off on. app/priority/
calculate.py reads every threshold and weight from these rows; it never
hardcodes one.
"""

from datetime import datetime

from sqlalchemy import Boolean, CheckConstraint, DateTime, Float, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class PrioritySettings(Base):
    """Single-row table (always id=1), same idiom as RatingSettings/
    LearningSettings -- created lazily with defaults on first read.

    Holds the two things that don't belong to any one band list: how much
    each of the 4 factors (word level, recent errors, recency, stability)
    counts relative to the others, and how much each of the 3 fixed
    recent-error windows (last 5 / last 10 / last 20 attempts) counts
    relative to each other within the "recent errors" factor."""

    __tablename__ = "priority_settings"

    id: Mapped[int] = mapped_column(primary_key=True)

    weight_level: Mapped[float] = mapped_column(Float, nullable=False, default=1.0, server_default="1")
    weight_recent_errors: Mapped[float] = mapped_column(Float, nullable=False, default=1.0, server_default="1")
    weight_recency: Mapped[float] = mapped_column(Float, nullable=False, default=1.0, server_default="1")
    weight_stability: Mapped[float] = mapped_column(Float, nullable=False, default=1.0, server_default="1")

    window5_weight: Mapped[float] = mapped_column(Float, nullable=False, default=1.0, server_default="1")
    window10_weight: Mapped[float] = mapped_column(Float, nullable=False, default=0.6, server_default="0.6")
    window20_weight: Mapped[float] = mapped_column(Float, nullable=False, default=0.3, server_default="0.3")

    # How many of the most recent attempts the stability factor looks at
    # (the spec's own examples all use 10, but nothing says it must stay
    # fixed -- kept here rather than hardcoded in app/priority/calculate.py).
    stability_window: Mapped[int] = mapped_column(Integer, nullable=False, default=10, server_default="10")

    # Personal auto-quests (see app/priority/quests_auto.py): a word counts
    # as "weak" in one exercise if it has at least this many attempts
    # there AND its error rate there is at least this fraction (0-1).
    # Every number below is a starting example, same discipline as the
    # rest of this table -- none of it is spec-fixed business math.
    personal_quest_min_attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=2, server_default="2")
    personal_quest_weak_error_rate: Mapped[float] = mapped_column(Float, nullable=False, default=0.5, server_default="0.5")
    # How many High/Medium-priority words weak in the SAME exercise must
    # accumulate before a personal quest is created for it, and the most
    # it will ever bundle into one.
    personal_quest_min_words: Mapped[int] = mapped_column(Integer, nullable=False, default=3, server_default="3")
    personal_quest_max_words: Mapped[int] = mapped_column(Integer, nullable=False, default=5, server_default="5")
    # Rating bonus a personal quest grants on a successful word -- separate
    # from any admin Quest's own reward_points, since a personal quest has
    # no admin-authored Quest row of its own to read it from.
    personal_quest_reward_points: Mapped[int] = mapped_column(Integer, nullable=False, default=10, server_default="10")

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class PriorityRecencyBand(Base):
    """One "haven't touched this word in N days" band -- exact same shape
    as WordLevel (a range + a contribution + admin display order), just
    over days-since-last-attempt instead of score. `max_days=None` means
    no upper bound (the "11+ days" band)."""

    __tablename__ = "priority_recency_bands"
    __table_args__ = (
        CheckConstraint("max_days IS NULL OR max_days >= min_days", name="ck_priority_recency_range_valid"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    min_days: Mapped[int] = mapped_column(Integer, nullable=False)
    max_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    contribution: Mapped[float] = mapped_column(Float, nullable=False, default=0, server_default="0")
    order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class PriorityStabilityBand(Base):
    """One "how steady are the recent results" band, by percent correct
    among the last-N attempts considered (see app/priority/calculate.py).
    Same range+contribution+order shape as every other band table here."""

    __tablename__ = "priority_stability_bands"
    __table_args__ = (
        CheckConstraint("max_percent >= min_percent", name="ck_priority_stability_range_valid"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    min_percent: Mapped[int] = mapped_column(Integer, nullable=False)
    max_percent: Mapped[int] = mapped_column(Integer, nullable=False)
    contribution: Mapped[float] = mapped_column(Float, nullable=False, default=0, server_default="0")
    order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class PriorityLevelBand(Base):
    """Maps a computed Priority Score to one of the five named levels
    (Критический / Высокий / Средний / Низкий / Минимальный, though the
    names themselves are this table's own data, never hardcoded) --
    same range+order shape as WordLevel, over the Priority Score's own
    scale rather than WordProgress.score."""

    __tablename__ = "priority_level_bands"
    __table_args__ = (
        CheckConstraint("max_score IS NULL OR max_score >= min_score", name="ck_priority_level_range_valid"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    min_score: Mapped[float] = mapped_column(Float, nullable=False)
    max_score: Mapped[float | None] = mapped_column(Float, nullable=True)
    order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
