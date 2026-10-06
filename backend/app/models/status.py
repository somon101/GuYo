"""Leaderboard statuses: the emoji and the short motivational phrase a
user shows next to their name in the rating.

Both lists belong to the admin. A user only ever picks from them -- never
types their own text or uses a system emoji -- so every status looks the
same on every phone and nothing unmoderated reaches the leaderboard.
"""

from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class StatusEmoji(Base):
    """One emoji, as GuYo's own picture rather than a system glyph."""

    __tablename__ = "status_emojis"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(64), nullable=False)
    image_key: Mapped[str] = mapped_column(String(500), nullable=False)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class StatusPhrase(Base):
    """One phrase a user can show, e.g. "Я буду первым!"."""

    __tablename__ = "status_phrases"

    id: Mapped[int] = mapped_column(primary_key=True)
    text: Mapped[str] = mapped_column(String(60), nullable=False)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
