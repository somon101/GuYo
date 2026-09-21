"""Word reinforcement levels: replaces the single global "learned
threshold" (LearningSettings.threshold_score) with an admin-defined
ladder. Mirrors app/models/rating.py's Rank exactly -- a definition table,
never hardcoded level names/thresholds in Flutter or backend logic.

The TOP enabled level (highest min_points) becomes the new "is this word
learned" threshold -- see app/exercises/common.py's get_threshold(), whose
call sites everywhere else are completely unchanged by this.
"""

from datetime import datetime

from sqlalchemy import Boolean, CheckConstraint, DateTime, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class WordLevel(Base):
    """One level definition (e.g. "Закреплено", min_points=80) an admin
    created. `max_points=None` means no upper bound (the top level).
    `order` is the admin's own display ordering in Admin Web -- never
    inferred from min_points, so ranges can be added/edited freely without
    the list jumping around."""

    __tablename__ = "word_levels"
    __table_args__ = (
        CheckConstraint("max_points IS NULL OR max_points >= min_points", name="ck_word_level_range_valid"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    min_points: Mapped[int] = mapped_column(Integer, nullable=False)
    max_points: Mapped[int | None] = mapped_column(Integer, nullable=True)
    order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
