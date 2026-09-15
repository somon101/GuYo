from datetime import datetime

from sqlalchemy import Boolean, DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base

# The three languages that exist out of the box. An admin can still add any
# other language through the Admin Web "Добавить новый язык" form -- these
# are just the ready-made shortcuts, not a hard limit. Dictionary.language
# stores whichever of these short codes was picked, or the raw typed text
# for a custom language (there's nothing to look up for those: the typed
# text *is* the display label).
DEFAULT_DICTIONARY_LANGUAGES: dict[str, str] = {
    "en": "English",
    "ru": "Русский",
    "zh": "中文",
}


def resolve_dictionary_language_label(language: str) -> str:
    """The dictionary's display name, derived from its language -- an admin
    no longer types a separate name at all."""
    return DEFAULT_DICTIONARY_LANGUAGES.get(language, language)


class Dictionary(Base):
    __tablename__ = "dictionaries"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(128), nullable=False)
    # Plain string, not a DB enum: an admin can add a brand new language at
    # any time from the UI, which a fixed enum can't accommodate without a
    # migration for every single language ever added.
    language: Mapped[str] = mapped_column(String(64), nullable=False)
    # Publication is a single flag for the whole dictionary (and therefore
    # every Word in it) -- there is deliberately no per-Word publish state.
    is_published: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false", default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    words: Mapped[list["Word"]] = relationship(
        back_populates="dictionary", cascade="all, delete-orphan", order_by="Word.id"
    )
