from datetime import datetime

from sqlalchemy import DateTime, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class ExerciseSettings(Base):
    """Per-exercise admin configuration -- for now just how many words one
    run of the exercise uses.

    Keyed by a plain string `exercise_key` ("true_or_false" today) rather
    than one table/column per exercise: a future exercise, or
    "Сопоставление" adopting the same admin-configurable count, is just a
    new key value, never a schema change. Mirrors this project's existing
    convention of plain-string keys over DB enums (see e.g. Dictionary.
    language) for the same reason -- extending the set never needs a
    migration."""

    __tablename__ = "exercise_settings"

    id: Mapped[int] = mapped_column(primary_key=True)
    exercise_key: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)
    word_count: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
