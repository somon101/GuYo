from datetime import datetime

from sqlalchemy import DateTime, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

# A GuYo account number is always exactly 9 digits -- no shorter, no
# longer, digits only. Kept as the bounds themselves rather than a length
# check so "generate one" and "is this one valid" can never disagree.
PUBLIC_ID_MIN = 100_000_000
PUBLIC_ID_MAX = 999_999_999


class User(Base):
    """A GuYo end user (the person using the Flutter app).

    `id` is this user's one permanent internal identifier -- every other
    table that belongs to a user (WordProgress, Lesson, UserAchievement,
    ...) references it, and so does the auth token. It is never shown to
    anyone and never changes.

    `public_id` is the 9-digit account number the user actually sees, in
    their profile and in Admin Web. It is deliberately a separate column
    rather than the primary key: making the key itself 9 digits would mean
    rewriting every one of those foreign keys and invalidating every
    issued token, for a number whose only job is to be read aloud. Unique,
    so it identifies an account on its own.

    `login` is credentials/display text and is free to change; nothing
    should ever treat it as a stable identity -- that is what `id` is for.

    `first_name`, `last_name` and `email` are required of every NEW
    account (see app/schemas/user.py's UserCreate) but nullable in the
    database, because accounts created before they existed simply do not
    have them and must keep working. `email` is unique where present --
    Postgres allows any number of NULLs under a unique constraint, so
    older accounts are unaffected.

    `avatar_key` is this user's own uploaded profile photo (same storage-key
    convention as Word.image_key -- see app/core/storage.py), null until
    they upload one, at which point the client falls back to a generated
    default avatar instead of assuming a photo exists."""

    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    public_id: Mapped[int] = mapped_column(Integer, unique=True, index=True, nullable=False)
    login: Mapped[str] = mapped_column(String(64), unique=True, index=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    first_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    last_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    email: Mapped[str | None] = mapped_column(String(255), unique=True, index=True, nullable=True)
    avatar_key: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
