from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, Integer, String, UniqueConstraint, func, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class LearnedWord(Base):
    """Marks that a User has learned a specific Word (by word_id). This is
    the ONLY place "learned" state lives -- no copy of Word is ever made.
    A user learning the same word twice must never create two rows, hence
    the unique constraint (this is the idempotency guarantee for "Изучил",
    enforced at the database level, not just in the endpoint logic)."""

    __tablename__ = "learned_words"
    __table_args__ = (UniqueConstraint("user_id", "word_id", name="uq_learned_word_user_word"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    word_id: Mapped[int] = mapped_column(ForeignKey("words.id", ondelete="CASCADE"), nullable=False, index=True)
    learned_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class LearningSession(Base):
    """One "Изучение слов" run for a user, scoped to one language block. Its
    fixed set of words lives on LearningSessionItem -- created once, never
    re-randomized, and read back the same way after the app is closed and
    reopened (this row -- not any client-side state -- is what makes a
    session survive a restart).

    At most one INCOMPLETE session may exist per (user, dictionary): the
    partial unique index below enforces that at the database level, so a
    race between two requests can't ever produce two active sessions for
    the same language."""

    __tablename__ = "learning_sessions"
    __table_args__ = (
        Index(
            "uq_active_learning_session_per_user_dictionary",
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
    is_completed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    items: Mapped[list["LearningSessionItem"]] = relationship(
        back_populates="session", cascade="all, delete-orphan"
    )


class LearningSessionItem(Base):
    """One word_id in a session's fixed set, plus its progress.

    `status` is one of "new" (never shown a decision yet), "review" (user
    tapped "Ещё раз буду изучать" at least once) or "learned". `position`
    is a simple integer queue order: the next word to show is always the
    lowest `position` among non-learned items. Sending a word to review
    doesn't remove or duplicate it -- it just gets a position past every
    other currently-outstanding item, so it naturally comes back only after
    the rest of the current round has been shown, reproducing the "repeat
    cycle" behavior without tracking explicit round boundaries."""

    __tablename__ = "learning_session_items"
    __table_args__ = (UniqueConstraint("session_id", "word_id", name="uq_session_item_session_word"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    session_id: Mapped[int] = mapped_column(
        ForeignKey("learning_sessions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    word_id: Mapped[int] = mapped_column(ForeignKey("words.id", ondelete="CASCADE"), nullable=False, index=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="new", server_default="new")
    position: Mapped[int] = mapped_column(Integer, nullable=False)

    session: Mapped["LearningSession"] = relationship(back_populates="items")
    word: Mapped["Word"] = relationship()
