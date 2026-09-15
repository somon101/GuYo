import enum
from datetime import datetime

from sqlalchemy import DateTime, Enum, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class DictionaryLanguage(str, enum.Enum):
    """The only three languages supported at this stage."""

    ENGLISH = "en"
    RUSSIAN = "ru"
    CHINESE = "zh"


class Dictionary(Base):
    __tablename__ = "dictionaries"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(128), nullable=False)
    language: Mapped[DictionaryLanguage] = mapped_column(
        Enum(
            DictionaryLanguage,
            name="dictionary_language",
            values_callable=lambda enum_cls: [member.value for member in enum_cls],
        ),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    words: Mapped[list["Word"]] = relationship(
        back_populates="dictionary", cascade="all, delete-orphan", order_by="Word.id"
    )
