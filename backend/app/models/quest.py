"""Quests: a fully separate system from both Achievements and the plain
seasonal rating grant path (app/rating/) -- reusing only UserRating as the
one place points ever land (see app/rating/service.py's
grant_rating_points), never Achievement/UserAchievement, never a second
rating ledger.
"""

from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Quest(Base):
    """One quest DEFINITION an admin created -- e.g. "level 3 words,
    Собери слово exercise, +10 rating points". `exercise_key` is one of
    the 5 word-scoped exercise types already registered in
    app/exercises/__init__.py's EXERCISE_TYPES (matching, true_or_false,
    build_word, speaking_word, listen_word) -- never a free-text field,
    validated against that same registry in the admin router.

    The word-reinforcement point change on success reuses that
    exercise_key's OWN already-configured ExerciseSettings.correct_points
    (see app/exercises/common.py's get_points) -- there is no second,
    quest-specific reinforcement-points setting. `reward_points` is purely
    the ADDITIONAL rating bonus on top of that, and is the only thing this
    model defines that Lessons don't already have.

    `daily_target` is how many successful attempts count as "this quest is
    done for today" -- purely the goal a progress bar fills toward, NOT a
    second reward rule: every successful attempt still grants
    `reward_points` exactly as before, target reached or not. Progress
    itself is counted from the UserQuestWordDay rows that already exist
    (one per word this quest consumed today), never stored separately."""

    __tablename__ = "quests"
    __table_args__ = (CheckConstraint("daily_target >= 1", name="ck_quest_daily_target_positive"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    word_level_id: Mapped[int] = mapped_column(ForeignKey("word_levels.id", ondelete="RESTRICT"), nullable=False)
    exercise_key: Mapped[str] = mapped_column(String(64), nullable=False)
    reward_points: Mapped[int] = mapped_column(Integer, nullable=False)
    daily_target: Mapped[int] = mapped_column(Integer, nullable=False, default=1, server_default="1")
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class UserQuestWordDay(Base):
    """Proof a specific (user, word) pair already completed SOME quest
    today -- the one thing that guarantees "a word can be used in at most
    one quest per day", across ALL quests, exactly mirroring
    UserActivityDay's own per-day uniqueness role (see
    app/models/achievement.py). `used_date` is the server's own
    Asia/Dushanbe date (app/core/dates.py's dushanbe_today) -- GuYo's
    quests reset on Tajikistan's own clock, deliberately NOT UTC and
    never the phone's own timezone, so every user sees the same reset
    moment regardless of where their device thinks it is.

    `quest_id` is kept only as a record of which quest actually used the
    word that day (useful for admin visibility); it plays no part in the
    uniqueness rule itself, which is keyed on (user_id, word_id,
    used_date) alone -- a word used by Quest A this morning must also
    block Quest B this afternoon, not just a repeat of Quest A."""

    __tablename__ = "user_quest_word_days"
    __table_args__ = (UniqueConstraint("user_id", "word_id", "used_date", name="uq_user_quest_word_day"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    word_id: Mapped[int] = mapped_column(ForeignKey("words.id", ondelete="CASCADE"), nullable=False, index=True)
    quest_id: Mapped[int] = mapped_column(ForeignKey("quests.id", ondelete="CASCADE"), nullable=False)
    used_date: Mapped[date] = mapped_column(Date, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
