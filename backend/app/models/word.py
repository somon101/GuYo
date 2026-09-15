from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Word(Base):
    """A single vocabulary entry, addressable by its own id (`word_id`).

    This is the core reusable entity of GuYo: exercises, tests, games and
    flashcards that get built later will all reference an existing Word by
    id rather than duplicating the word/translation text."""

    __tablename__ = "words"

    id: Mapped[int] = mapped_column(primary_key=True)
    dictionary_id: Mapped[int] = mapped_column(
        ForeignKey("dictionaries.id", ondelete="CASCADE"), nullable=False, index=True
    )

    word: Mapped[str] = mapped_column(String(255), nullable=False)
    translation: Mapped[str] = mapped_column(String(255), nullable=False)
    transcription: Mapped[str | None] = mapped_column(String(255), nullable=True)

    # Storage keys (relative paths), not raw bytes -- see app/core/storage.py.
    word_audio_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    translation_audio_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    image_key: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    dictionary: Mapped["Dictionary"] = relationship(back_populates="words")
