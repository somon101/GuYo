from datetime import datetime

from sqlalchemy import JSON, DateTime, ForeignKey, Index, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class UserEvent(Base):
    """One step of a learner's history that is not an answer (answers are
    WordAttempt rows): a lesson created/opened/left/completed, a personal
    quest created, a quest opened or answered, the app opened. Together
    with WordAttempt it is the timeline Admin Web shows per user
    (app/analytics/history.py). Purely a record -- no learning logic reads it.
    `data` holds the few extra facts a kind needs (lesson number...)."""

    __tablename__ = "user_events"
    __table_args__ = (Index("ix_user_events_user_created", "user_id", "created_at"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    kind: Mapped[str] = mapped_column(String(32), nullable=False)
    lesson_id: Mapped[int | None] = mapped_column(ForeignKey("lessons.id", ondelete="SET NULL"), nullable=True)
    quest_id: Mapped[int | None] = mapped_column(ForeignKey("quests.id", ondelete="SET NULL"), nullable=True)
    data: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
