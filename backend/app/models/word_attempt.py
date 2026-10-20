"""One row per real answer to a word (lesson, quest, practice, review).
The memory model rebuilds a word's state from these (app/memory/), a lesson
pass decides which words became learned from them (app/learning/mastery.py),
and Admin Web's «Аналитика» shows them as history.
"""

from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class WordAttempt(Base):
    __tablename__ = "word_attempts"
    __table_args__ = (
        # The one access pattern this table exists for: "every attempt
        # this user has made on this word, in order" -- Admin Web's word
        # diagnostics page.
        Index("ix_word_attempts_user_word", "user_id", "word_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    word_id: Mapped[int] = mapped_column(ForeignKey("words.id", ondelete="CASCADE"), nullable=False, index=True)
    exercise_key: Mapped[str] = mapped_column(String(64), nullable=False)
    is_correct: Mapped[bool] = mapped_column(Boolean, nullable=False)
    # The lesson this answer was given in, for a lesson's own end-of-pass
    # statistics (GET /lessons/{id}/pass/stats). NULL for quest answers
    # and for every attempt recorded before this column existed.
    lesson_id: Mapped[int | None] = mapped_column(
        ForeignKey("lessons.id", ondelete="SET NULL"), nullable=True, index=True
    )
    # Where the answer was given: "lesson", "quest" or "practice". Practice
    # answers change no score -- they are recorded only as memory evidence.
    source: Mapped[str] = mapped_column(String(16), nullable=False, default="lesson", server_default="lesson")
    # How long the item was on screen before the answer, as measured by the
    # app; NULL when unknown (older app versions, the matching board).
    duration_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    # The countdown ran out: counted as not recalled, but weaker evidence
    # of forgetting than picking a wrong answer.
    # What the learner actually gave when it differs from a tap on right/
    # wrong: the picked option, the built letters, the recognized speech.
    given_answer: Mapped[str | None] = mapped_column(String(255), nullable=True)
    # Where the word was shown, when the app says: the phrase / mini-phrase
    # of the exercise, and the «Повторить сегодня» list it was reviewed in.
    phrase_id: Mapped[int | None] = mapped_column(ForeignKey("phrases.id", ondelete="SET NULL"), nullable=True)
    mini_phrase_id: Mapped[int | None] = mapped_column(
        ForeignKey("mini_phrases.id", ondelete="SET NULL"), nullable=True
    )
    review_list_id: Mapped[int | None] = mapped_column(
        ForeignKey("review_lists.id", ondelete="SET NULL"), nullable=True, index=True
    )
    timed_out: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True)
