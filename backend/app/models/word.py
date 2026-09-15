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
    WordTranslation instead -- see that class for why. Grammatical forms
    live on WordForm for the same reason: a word can have any number of
    forms, in more than one language, without a hardcoded column per
    language or per form slot."""

    __tablename__ = "words"

    id: Mapped[int] = mapped_column(primary_key=True)
    dictionary_id: Mapped[int] = mapped_column(
        ForeignKey("dictionaries.id", ondelete="CASCADE"), nullable=False, index=True
    )
    # Optional grouping for the dictionary's category view. Never required,
    # never changes word_id, never duplicates the Word.
    category_id: Mapped[int | None] = mapped_column(
        ForeignKey("categories.id", ondelete="SET NULL"), nullable=True, index=True
    )

    word: Mapped[str] = mapped_column(String(255), nullable=False)
    transcription: Mapped[str | None] = mapped_column(String(255), nullable=True)

    # Storage keys (relative paths), not raw bytes -- see app/core/storage.py.
    word_audio_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    image_key: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    dictionary: Mapped["Dictionary"] = relationship(back_populates="words")
    category: Mapped["Category | None"] = relationship(back_populates="words")
    translations: Mapped[list["WordTranslation"]] = relationship(
        back_populates="word", cascade="all, delete-orphan", order_by="WordTranslation.id"
    )
    forms: Mapped[list["WordForm"]] = relationship(
        back_populates="word", cascade="all, delete-orphan", order_by="WordForm.id"
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


class WordForm(Base):
    """One grammatical/inflected form of a Word, in a given language (e.g.
    the "go / goes / went / gone / going" forms of "go" in English, or its
    Tajik forms). Deliberately unbounded and unconstrained per language --
    unlike WordTranslation there is no uniqueness constraint here, since a
    word legitimately has *several* forms in the same language. Order is
    the insertion order (ascending id), matching how forms are only ever
    appended via "Добавить ещё", never reordered."""

    __tablename__ = "word_forms"

    id: Mapped[int] = mapped_column(primary_key=True)
    word_id: Mapped[int] = mapped_column(ForeignKey("words.id", ondelete="CASCADE"), nullable=False, index=True)

    language: Mapped[str] = mapped_column(String(8), nullable=False)
    text: Mapped[str] = mapped_column(String(255), nullable=False)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    word: Mapped["Word"] = relationship(back_populates="forms")
