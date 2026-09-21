from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class ExerciseSettings(Base):
    """Per-exercise admin configuration.

    Keyed by a plain string `exercise_key` ("true_or_false", "matching",
    "build_word" today) rather than one table/column per exercise: a
    future exercise is just a new key value, never a schema change.
    Mirrors this project's existing convention of plain-string keys over
    DB enums (see e.g. Dictionary.language) for the same reason --
    extending the set never needs a migration.

    `word_count` applies to every exercise built this way. The remaining
    three columns are extra knobs only "Собери слово" uses today (how many
    wrong distractor letters, the shortest word it'll pick, whether
    comparison is case-sensitive) -- left null and ignored by every other
    exercise_key, same as any other exercise-specific setting a future one
    might need.

    `correct_points`/`incorrect_points` are how much a right/wrong answer
    to this exercise moves a word's WordProgress.score (see
    app/models/word_progress.py) -- e.g. Сопоставление +20/-10, Правда или
    ложь +10/-5. Nullable with a code-level default per exercise_key (see
    app/exercises/common.py), same reasoning as the three columns above:
    an admin can leave these unset and the exercise still works.

    `enabled` gates whether this exercise_key can ever be picked for a new
    Lesson at all (see app/exercises/__init__.py's EXERCISE_TYPES dispatch)
    -- null/true means enabled, same nullable-defaults-to-working pattern
    as everything else here. `option_count` is "Услышь слово"'s own knob
    (how many word choices one round shows); `speech_match_threshold` is
    "Произнеси слово"'s own knob (0-100 minimum text-similarity to accept
    a spoken answer as correct) -- both null/ignored for every other
    exercise_key, same convention as wrong_letter_count etc."""

    __tablename__ = "exercise_settings"

    id: Mapped[int] = mapped_column(primary_key=True)
    exercise_key: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)
    word_count: Mapped[int] = mapped_column(Integer, nullable=False)
    wrong_letter_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    min_word_length: Mapped[int | None] = mapped_column(Integer, nullable=True)
    case_sensitive: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    correct_points: Mapped[int | None] = mapped_column(Integer, nullable=True)
    incorrect_points: Mapped[int | None] = mapped_column(Integer, nullable=True)
    enabled: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    option_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    speech_match_threshold: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
