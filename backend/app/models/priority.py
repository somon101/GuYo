"""Priority: an analytics layer computed ON TOP of WordProgress -- never a
second progress system. app/priority/calculate.py maps the memory model's
recall probability onto these named levels using the settings row below.
"""

from datetime import datetime

from sqlalchemy import Boolean, CheckConstraint, DateTime, Float, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class PrioritySettings(Base):
    """Single-row table (always id=1), same idiom as RatingSettings/
    LearningSettings -- created lazily with defaults on first read.

    Holds the memory model's cut-offs and the auto-quest / auto-lesson
    numbers."""

    __tablename__ = "priority_settings"

    id: Mapped[int] = mapped_column(primary_key=True)

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

    # Adaptive lessons (app/priority/lessons.py): how many words whose Priority
    # role is "critical" must accumulate before one is built automatically.
    # Was hardcoded at 5 (the spec's own example); an admin number now, so it
    # can be raised to make auto lessons rarer or lowered to make them appear
    # sooner.
    adaptive_lesson_min_words: Mapped[int] = mapped_column(Integer, nullable=False, default=5, server_default="5")

    # The memory model (app/memory/): a word's Priority level comes from its
    # recall probability R, and a learned word whose R fell below the target
    # needs review again.
    memory_target_retention: Mapped[float] = mapped_column(Float, nullable=False, default=0.9, server_default="0.9")
    memory_critical_below: Mapped[float] = mapped_column(Float, nullable=False, default=0.7, server_default="0.7")
    memory_high_below: Mapped[float] = mapped_column(Float, nullable=False, default=0.85, server_default="0.85")
    memory_minimal_above: Mapped[float] = mapped_column(Float, nullable=False, default=0.95, server_default="0.95")

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class PriorityLevelBand(Base):
    """Maps a word's Priority to one of the five named levels
    (Критический / Высокий / Средний / Низкий / Минимальный, though the
    names themselves are this table's own data, never hardcoded) --
    ranked by min_score; app/priority/settings.py's priority_role_bands
    gives each rank its role."""

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
