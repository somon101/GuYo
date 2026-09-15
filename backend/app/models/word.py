from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Word(Base):
    """A single vocabulary entry, addressable by its own id (`word_id`).

    This is the core reusable entity of GuYo: exercises, tests, games and
    flashcards that get built later will all reference an existing Word by
    id rather than duplicating the word/translation text.

    Everything here is specific to the word itself, in the dictionary's own
    language: the word text, its transcription and its own pronunciation.
    Translations (which may exist in several other languages) live on
    WordTranslation instead -- see that class for why."""

    __tablename__ = "words"

    id: Mapped[int] = mapped_column(primary_key=True)
    dictionary_id: Mapped[int] = mapped_column(
        ForeignKey("dictionaries.id", ondelete="CASCADE"), nullable=False, index=True
    )

    word: Mapped[str] = mapped_column(String(255), nullable=False)
    transcription: Mapped[str | None] = mapped_column(String(255), nullable=True)

    # Storage keys (relative paths), not raw bytes -- see app/core/storage.py.
    word_audio_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    image_key: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Free-form external study-resource link (e.g. a Quizlet set/card URL).
    # A single field is enough for now -- nothing today asks for more than
    # one per word.
    quizlet: Mapped[str | None] = mapped_column(String(500), nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    dictionary: Mapped["Dictionary"] = relationship(back_populates="words")
    translations: Mapped[list["WordTranslation"]] = relationship(
        back_populates="word", cascade="all, delete-orphan", order_by="WordTranslation.id"
    )


class WordTranslation(Base):
    """One translation of a Word into a specific language, with its own
    optional pronunciation audio.

    This is a separate entity (rather than `translation` / `translation_audio`
    columns on Word) specifically so a word can carry translations into
    several languages at once -- e.g. Russian and Tajik -- without adding a
    new hardcoded column for every language GuYo ever supports. The language
    is a plain string (not a DB enum) so a new language needs no migration,
    just a new allowed value in the API layer."""

    __tablename__ = "word_translations"
    __table_args__ = (UniqueConstraint("word_id", "language", name="uq_word_translation_language"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    word_id: Mapped[int] = mapped_column(ForeignKey("words.id", ondelete="CASCADE"), nullable=False, index=True)

    language: Mapped[str] = mapped_column(String(8), nullable=False)
    text: Mapped[str] = mapped_column(String(255), nullable=False)
    audio_key: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    word: Mapped["Word"] = relationship(back_populates="translations")
