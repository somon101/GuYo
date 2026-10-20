"""The chest of the day: one small random bonus per person per day, opened
after the first study of that day."""

from datetime import date, datetime

from sqlalchemy import Date, DateTime, ForeignKey, Integer, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class DailyChest(Base):
    __tablename__ = "daily_chests"
    __table_args__ = (UniqueConstraint("user_id", "chest_date", name="uq_daily_chest_once"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    chest_date: Mapped[date] = mapped_column(Date, nullable=False)
    kind: Mapped[str] = mapped_column(String(12), nullable=False)  # "xp" | "freeze"
    amount: Mapped[int] = mapped_column(Integer, nullable=False)
    opened_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
