"""One row per real answer to a word, in a Lesson or a Quest -- the two
places an answer actually changes WordProgress.score (see
app/routers/lessons.py's submit_answer and app/routers/quests.py's
submit_quest_answer). Practice deliberately writes nothing here: it never
touches score/progress at all, so it has no "attempt" to record in this
sense -- see app/routers/practice.py's own docstring.

This is purely an analytics log for Admin Web's «Аналитика» -- nothing
in the actual scoring/level/achievement/rating pipeline ever reads from
it. Deleting every row here would not change what a single user's word
score or level is; it would only make their history page blank.
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
    # WordProgress.score for this (user, word) immediately AFTER this
    # attempt was scored -- captured at write time rather than replayed
    # later from is_correct history, because the admin-configured
    # correct/incorrect point deltas for an exercise_key can change over
    # time; a replay using TODAY's settings would silently misdraw the
    # history of an account that predates a settings change. This column
    # is the one honest source for "what was the score at this moment".
    score_after: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True)
