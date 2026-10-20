"""A one-week duel between two friends: who earns more season XP that week.
Scores are never stored: they are counted from the XP ledger (PassXpEvent)."""

from datetime import date, datetime

from sqlalchemy import Date, DateTime, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

PENDING, ACTIVE, DECLINED, FINISHED, CANCELLED = "pending", "active", "declined", "finished", "cancelled"


class Duel(Base):
    __tablename__ = "duels"

    id: Mapped[int] = mapped_column(primary_key=True)
    challenger_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    opponent_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    # The Monday of the duel's week (Dushanbe); it ends the next Monday.
    week_start: Mapped[date] = mapped_column(Date, nullable=False)
    status: Mapped[str] = mapped_column(String(12), nullable=False, default=PENDING, server_default=PENDING, index=True)
    winner_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    challenger_xp: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    opponent_xp: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
