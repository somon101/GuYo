from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, String, UniqueConstraint, func, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Lesson(Base):
    """One "Урок" run: a fixed, admin-size-capped (<=15) set of word_ids the
    user picked (randomly or by hand) for a dictionary, plus whichever
    exercise types turned out to be available for that exact set (see
    LessonExercise). Nothing here duplicates Word -- see LessonWord.

    `number` is the user-facing "Урок N" label, sequential per (user,
    dictionary) starting at 1. At most one INCOMPLETE lesson may exist per
    (user, dictionary) -- the partial unique index below enforces that at
    the database level, mirroring LearningSession's own guarantee -- so a
    new lesson can never be created while the current one still has words
    below the learning threshold."""

    __tablename__ = "lessons"
    __table_args__ = (
        Index(
            "uq_active_lesson_per_user_dictionary",
            "user_id",
            "dictionary_id",
            unique=True,
            postgresql_where=text("is_completed = false"),
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    dictionary_id: Mapped[int] = mapped_column(
        ForeignKey("dictionaries.id", ondelete="CASCADE"), nullable=False, index=True
    )
    number: Mapped[int] = mapped_column(nullable=False)
    is_completed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    # True for a lesson app/priority/ auto-created from 5 accumulated
    # Critical-priority words (see app/priority/lessons.py) -- otherwise
    # identical in every way to a random/manual lesson, same exercises,
    # same completion rule. Lets the accumulation check skip a word that's
    # already sitting in an incomplete adaptive lesson, without a second
    # table just to remember that.
    is_adaptive: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    words: Mapped[list["LessonWord"]] = relationship(back_populates="lesson", cascade="all, delete-orphan")
    exercises: Mapped[list["LessonExercise"]] = relationship(back_populates="lesson", cascade="all, delete-orphan")


class LessonWord(Base):
    """One word_id in a lesson's fixed set -- never a copy of Word, just the
    reference, exactly like LearningSessionItem did for the old system."""

    __tablename__ = "lesson_words"
    __table_args__ = (UniqueConstraint("lesson_id", "word_id", name="uq_lesson_word_lesson_word"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    lesson_id: Mapped[int] = mapped_column(ForeignKey("lessons.id", ondelete="CASCADE"), nullable=False, index=True)
    word_id: Mapped[int] = mapped_column(ForeignKey("words.id", ondelete="CASCADE"), nullable=False, index=True)

    lesson: Mapped["Lesson"] = relationship(back_populates="words")
    word: Mapped["Word"] = relationship()


class LessonExercise(Base):
    """One exercise type included in a lesson, decided once at lesson
    creation time by that exercise's own availability check (see
    app/routers/lessons.py's EXERCISE_AVAILABILITY) and never recomputed
    afterwards -- if "Правда или ложь" wasn't available when the lesson was
    created, it stays absent from this lesson even if the user later
    learns enough words to make it available for the *next* one.

    Keyed by the same plain-string `exercise_key` as ExerciseSettings
    ("true_or_false", "matching", "build_word") so a future exercise is
    just a new key, never a schema change."""

    __tablename__ = "lesson_exercises"
    __table_args__ = (UniqueConstraint("lesson_id", "exercise_key", name="uq_lesson_exercise_lesson_key"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    lesson_id: Mapped[int] = mapped_column(ForeignKey("lessons.id", ondelete="CASCADE"), nullable=False, index=True)
    exercise_key: Mapped[str] = mapped_column(String(64), nullable=False)

    lesson: Mapped["Lesson"] = relationship(back_populates="exercises")
