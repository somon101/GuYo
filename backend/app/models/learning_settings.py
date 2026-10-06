from datetime import datetime

from sqlalchemy import DateTime, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class LearningSettings(Base):
    """A single-row table (always id=1) holding the one admin-configured
    value that isn't specific to any one exercise: the "Проходной порог
    изучения слова" -- the WordProgress.score a word needs to reach before
    it counts as learned and a lesson containing it can complete. Kept as
    its own tiny table (rather than overloading ExerciseSettings, which is
    keyed per exercise_key) since this genuinely isn't an exercise
    setting."""

    __tablename__ = "learning_settings"

    id: Mapped[int] = mapped_column(primary_key=True)
    threshold_score: Mapped[int] = mapped_column(Integer, nullable=False, default=60, server_default="60")
    # The AI translator (app/translation/deepseek.py): its key, and the
    # progress of its current or last run ("idle"/"running"/"completed"/
    # "failed"/"stopped").
    deepseek_api_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    translate_status: Mapped[str] = mapped_column(String(16), nullable=False, default="idle", server_default="idle")
    translate_total: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    translate_done: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    translate_failed: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    translate_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
