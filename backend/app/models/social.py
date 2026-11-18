"""Requests between people: to become friends, and to join a closed team."""

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class FriendRequest(Base):
    """«Добавить в друзья»: waits until the other person answers. One per pair and direction."""

    __tablename__ = "friend_requests"
    __table_args__ = (UniqueConstraint("from_id", "to_id", name="uq_friend_request_pair"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    from_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    to_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class TeamJoinRequest(Base):
    """A request to join a closed team; only the team's creator answers it. A declined request stays
    (with `declined_at`) so the same person cannot ask again for a day."""

    __tablename__ = "team_join_requests"
    __table_args__ = (UniqueConstraint("team_id", "user_id", name="uq_team_join_request_once"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    team_id: Mapped[int] = mapped_column(ForeignKey("teams.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    declined_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
