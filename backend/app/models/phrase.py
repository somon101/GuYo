from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class PhraseCategory(Base):
    """A named grouping of phrases within one dictionary (language block).

    Deliberately a separate table from the word Category, even though the
    two work identically -- Words and Phrases are shown in their own tabs
    with their own independent category lists and counts, so sharing one
    table would either mix the two content types under the same category or
    require a discriminator column threaded through the existing, already
    working word-category code for no real benefit."""

    __tablename__ = "phrase_categories"
    __table_args__ = (UniqueConstraint("dictionary_id", "name", name="uq_phrase_category_dictionary_name"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    dictionary_id: Mapped[int] = mapped_column(
        ForeignKey("dictionaries.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(128), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    dictionary: Mapped["Dictionary"] = relationship()
    phrases: Mapped[list["Phrase"]] = relationship(back_populates="category")


class Phrase(Base):
    """A single phrase/sentence, addressable by its own id (`phrase_id`),
    same principle as Word/`word_id`: any future exercise, test or game
    references an existing Phrase by id instead of duplicating its text.

    Unlike Word, a phrase never carries multiple translations or forms --
    the product only needs one fixed pairing (the block's own language, and
    a Tajik translation), so those live as plain columns here rather than
    child tables. Each field (original, transcription, translation_tg, the
    two audio files) is independently nullable/optional except `original`
    and `translation_tg`, and can be read on its own via WordOut-style
    output without touching the others."""

    __tablename__ = "phrases"

    id: Mapped[int] = mapped_column(primary_key=True)
    dictionary_id: Mapped[int] = mapped_column(
        ForeignKey("dictionaries.id", ondelete="CASCADE"), nullable=False, index=True
    )
    category_id: Mapped[int | None] = mapped_column(
        ForeignKey("phrase_categories.id", ondelete="SET NULL"), nullable=True, index=True
    )

    original: Mapped[str] = mapped_column(String(1000), nullable=False)
    transcription: Mapped[str | None] = mapped_column(String(255), nullable=True)
    translation_tg: Mapped[str] = mapped_column(String(1000), nullable=False)

    # Storage keys (relative paths), not raw bytes -- see app/core/storage.py.
    original_audio_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    translation_audio_key: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    dictionary: Mapped["Dictionary"] = relationship()
    category: Mapped["PhraseCategory | None"] = relationship(back_populates="phrases")
