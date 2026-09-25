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
    """One quest DEFINITION -- either an admin-authored one (e.g. "level 3
    words, Собери слово exercise, +10 rating points"), or a PERSONAL one
    the backend created for a single user (see app/priority/quests_auto.py)
    when enough of their High/Medium-priority words turned out to share
    the same weak exercise. `owner_user_id` is the only thing that tells
    the two apart: None for an admin quest (unchanged from before this
    feature existed), set to a user's id for a personal one -- everything
    else in this table and the whole quest-serving flow (GET /quests,
    round building, answer submission, reward granting, the
    UserQuestWordDay daily lock) is shared code, unaware of which kind of
    Quest row it's looking at.

    `exercise_key` is one of the 5 word-scoped exercise types already
    registered in app/exercises/__init__.py's EXERCISE_TYPES (matching,
    true_or_false, build_word, speaking_word, listen_word) -- never a
    free-text field, validated against that same registry in the admin
    router (and, for personal quests, by construction in quests_auto.py).

    `word_level_id` is required for an admin quest (its one target level)
    but always None for a personal quest -- a personal quest's words come
    from Priority, not a single level range, and are pinned individually
    in QuestWord below instead.

    The word-reinforcement point change on success reuses that
    exercise_key's OWN already-configured ExerciseSettings.correct_points
    (see app/exercises/common.py's get_points) -- there is no second,
    quest-specific reinforcement-points setting. `reward_points` is purely
    the ADDITIONAL rating bonus on top of that (for a personal quest, this
    is PrioritySettings.personal_quest_reward_points, copied in at
    creation time -- see quests_auto.py).

    `daily_target` is how many successful attempts count as "this quest is
    done" -- for an admin quest that's a genuine daily goal (resets every
    day, every success still grants reward_points regardless). For a
    personal quest it means something else: simply how many of ITS OWN
    pinned QuestWord rows there are, i.e. "done" once every pinned word
    has been used once, ever (see app/quests/service.py's
    personal_quest_progress) -- the field is reused as-is because the
    client only ever displays {done}/{target}, never the word "daily"."""

    __tablename__ = "quests"
    __table_args__ = (CheckConstraint("daily_target >= 1", name="ck_quest_daily_target_positive"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    word_level_id: Mapped[int | None] = mapped_column(ForeignKey("word_levels.id", ondelete="RESTRICT"), nullable=True)
    exercise_key: Mapped[str] = mapped_column(String(64), nullable=False)
    reward_points: Mapped[int] = mapped_column(Integer, nullable=False)
    daily_target: Mapped[int] = mapped_column(Integer, nullable=False, default=1, server_default="1")
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    # None for an admin-authored quest (every quest before this feature
    # existed) -- set for a personal one. See this class's own docstring.
    owner_user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class QuestWord(Base):
    """The fixed word set behind ONE personal Quest (Quest.owner_user_id
    is set) -- exact same role LessonWord plays for Lesson: a snapshot
    decided once at creation time (app/priority/quests_auto.py), never
    recomputed. An admin-authored quest (owner_user_id None) has no rows
    here at all; its candidates come from the word-level range instead
    (see app/quests/service.py's candidate_words_for_quest)."""

    __tablename__ = "quest_words"
    __table_args__ = (UniqueConstraint("quest_id", "word_id", name="uq_quest_word"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    quest_id: Mapped[int] = mapped_column(ForeignKey("quests.id", ondelete="CASCADE"), nullable=False, index=True)
    word_id: Mapped[int] = mapped_column(ForeignKey("words.id", ondelete="CASCADE"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


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
