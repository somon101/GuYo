from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class ClientError(Base):
    """An error the mobile app caught and reported (POST /client-errors),
    so problems on users' phones are seen without waiting for screenshots.
    Purely a record for the team; nothing reads it to make decisions."""

    __tablename__ = "client_errors"

    id: Mapped[int] = mapped_column(primary_key=True)
    # Null when the app was not logged in yet.
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    app_build: Mapped[int | None] = mapped_column(Integer, nullable=True)
    platform: Mapped[str | None] = mapped_column(String(32), nullable=True)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    stack: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True)
