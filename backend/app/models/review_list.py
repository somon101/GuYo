"""«Повторить сегодня» as fixed lists (app/memory/review_lists.py).

A list is frozen the moment it is made: which words, and WHY each one
was put there (the memory model's numbers at that moment). Ordinary
lessons and quests never touch it -- only a right answer given while
reviewing the list ticks a word off. At most one list is active per
(user, dictionary); the rest wait in the queue, oldest first."""

from datetime import datetime

from sqlalchemy import DateTime, Float, ForeignKey, Index, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

STATUS_QUEUED = "queued"
STATUS_ACTIVE = "active"
STATUS_CLOSED = "closed"


class ReviewList(Base):
    __tablename__ = "review_lists"
    __table_args__ = (Index("ix_review_lists_user_dict_status", "user_id", "dictionary_id", "status"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    dictionary_id: Mapped[int] = mapped_column(ForeignKey("dictionaries.id", ondelete="CASCADE"), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default=STATUS_QUEUED)
    # The admin's «Повтори слово» number at the moment the list was made.
    size: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    activated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    closed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    # The push about this list went out (once per list).
    notified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class ReviewListWord(Base):
    __tablename__ = "review_list_words"

    id: Mapped[int] = mapped_column(primary_key=True)
    list_id: Mapped[int] = mapped_column(ForeignKey("review_lists.id", ondelete="CASCADE"), nullable=False, index=True)
    word_id: Mapped[int] = mapped_column(ForeignKey("words.id", ondelete="CASCADE"), nullable=False, index=True)
    # 1 = the most forgotten word of the list.
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    # Why it was chosen: the memory model's state when the list was made.
    recall: Mapped[float] = mapped_column(Float, nullable=False)
    target: Mapped[float] = mapped_column(Float, nullable=False)
    stability: Mapped[float | None] = mapped_column(Float, nullable=True)
    difficulty: Mapped[float | None] = mapped_column(Float, nullable=True)
    last_review: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    review_days: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    score: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    # The first right answer while reviewing this list; NULL = still to do.
    done_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
