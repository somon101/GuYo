"""Word levels: an admin-defined ladder a word climbs as the memory model
says it is remembered longer (min_days). Names and cut-offs are this table's
data, never hardcoded in Flutter or backend logic.
"""

from datetime import datetime

from sqlalchemy import Boolean, DateTime, Float, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class WordLevel(Base):
    """One level definition (e.g. "Закреплено", min_days=30) an admin
    created. `order` is the admin's own display ordering in Admin Web."""

    __tablename__ = "word_levels"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    # The memory-model ladder: a word is at this level while its memory
    # holds at least this many days (FSRS stability, app/memory/). Levels
    # are ordered by it.
    min_days: Mapped[float] = mapped_column(Float, nullable=False, default=0, server_default="0")
    order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
