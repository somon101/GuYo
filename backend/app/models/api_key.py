from datetime import datetime

from sqlalchemy import JSON, Boolean, DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class ApiKey(Base):
    """A key for the external API (/api/v1), created in Admin Web. Only its
    sha256 is stored -- the key itself is shown once, at creation. `scopes`
    says what it may touch (today: "achievements")."""

    __tablename__ = "api_keys"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    key_prefix: Mapped[str] = mapped_column(String(16), nullable=False)
    key_hash: Mapped[str] = mapped_column(String(64), nullable=False, unique=True, index=True)
    scopes: Mapped[list[str]] = mapped_column(JSON, nullable=False, default=list)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    last_used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
