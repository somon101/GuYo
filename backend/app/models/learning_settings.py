from datetime import datetime

from sqlalchemy import DateTime, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class LearningSettings(Base):
    """A single-row table (always id=1) for learning settings that aren't
    specific to any one exercise, plus the AI translator's state."""

    __tablename__ = "learning_settings"

    id: Mapped[int] = mapped_column(primary_key=True)
    # The most words one lesson can have (random count and manual pick alike),
    # set in Admin Web -> Упражнения.
    max_lesson_words: Mapped[int] = mapped_column(Integer, nullable=False, default=15, server_default="15")
    # The AI translator (app/translation/deepseek.py): its key, and the
    # progress of its current or last run ("idle"/"running"/"completed"/
    # "failed"/"stopped").
    deepseek_api_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    translate_status: Mapped[str] = mapped_column(String(16), nullable=False, default="idle", server_default="idle")
    translate_total: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    translate_done: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    translate_failed: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    translate_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Which language the last (or current) run translates into: "uz" / "en".
    translate_language: Mapped[str] = mapped_column(String(8), nullable=False, default="uz", server_default="uz")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
