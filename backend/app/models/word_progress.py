from datetime import datetime

from sqlalchemy import DateTime, Float, ForeignKey, Integer, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class WordProgress(Base):
    """One user's state for one Word: whether it is learned (`mastered_at`,
    app/learning/mastery.py) and how well it is remembered (the memory
    model's columns, app/memory/). Global per (user, word), not per lesson;
    a Word is never copied here, only referenced by word_id."""

    __tablename__ = "word_progress"
    __table_args__ = (
        UniqueConstraint("user_id", "word_id", name="uq_word_progress_user_word"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    word_id: Mapped[int] = mapped_column(ForeignKey("words.id", ondelete="CASCADE"), nullable=False, index=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    # The memory model (app/memory/): FSRS stability (days until recall
    # drops to 90%) and difficulty (1-10), rebuilt from this pair's answer
    # history one day at a time. NULL until the pair has been modelled.
    memory_stability: Mapped[float | None] = mapped_column(Float, nullable=True)
    memory_difficulty: Mapped[float | None] = mapped_column(Float, nullable=True)
    memory_last_review: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    # When this word became learned ("изучено"): set once, by a lesson pass
    # that proved it (app/learning/mastery.py), and never cleared -- a learned
    # word stays in "Мои слова" however much it is forgotten later; how well it
    # is remembered is the memory model's business. NULL = not learned yet.
    mastered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
    memory_review_days: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
