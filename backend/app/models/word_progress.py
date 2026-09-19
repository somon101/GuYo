from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Integer, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class WordProgress(Base):
    """A user's accumulated score for one Word (0-100), the ONLY source of
    truth for whether that word is "learned" now: `score >= the admin's
    configured threshold` (see LearningSettings). Global per (user, word),
    not per-lesson -- a word already at 60+ score from a past lesson is
    simply never offered as a pick for a new one, and its score keeps
    accumulating (clamped to 100) if it ever comes up again, rather than
    resetting. Replaces LearnedWord's old binary "is this word learned"
    role; a Word is never copied here, only referenced by word_id."""

    __tablename__ = "word_progress"
    __table_args__ = (
        UniqueConstraint("user_id", "word_id", name="uq_word_progress_user_word"),
        CheckConstraint("score >= 0 AND score <= 100", name="ck_word_progress_score_range"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    word_id: Mapped[int] = mapped_column(ForeignKey("words.id", ondelete="CASCADE"), nullable=False, index=True)
    score: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
