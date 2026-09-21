from datetime import datetime

from sqlalchemy import DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class User(Base):
    """A GuYo end user (the person using the Flutter app).

    `id` is this user's one permanent, unique identifier -- every other
    table that belongs to a user (WordProgress, Lesson, UserAchievement,
    ...) already references it, never `login`. `login` is only credentials/
    display text and is free to change meaning over time; nothing should
    ever treat it as a stable identity.

    `avatar_key` is this user's own uploaded profile photo (same storage-key
    convention as Word.image_key -- see app/core/storage.py), null until
    they upload one, at which point the client falls back to a generated
    default avatar instead of assuming a photo exists."""

    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    login: Mapped[str] = mapped_column(String(64), unique=True, index=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    avatar_key: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
