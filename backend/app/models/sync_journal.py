"""The sync journal: one row per action the app sent to sync a lesson pass.

A pass is handed over as three kinds of actions, in order -- opening the pass,
each answer, closing the pass (see app/routers/lessons.py). This table records
WHAT arrived and WHAT the server did with it, so "why does my lesson still read
0%?" is answerable without a debugger: open the lesson in the admin's sync
journal and see every packet, in the order it arrived, with the server's verdict.

Nothing here drives scoring: it is pure observation, written from the same call
that already decided the outcome, exactly like WordAttempt. Dropping or deleting
a row changes nothing about the user's progress.
"""

from datetime import datetime

from sqlalchemy import JSON, Boolean, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class SyncJournal(Base):
    __tablename__ = "sync_journal"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    user_login: Mapped[str] = mapped_column(String(64), nullable=False, default="", server_default="")
    lesson_id: Mapped[int | None] = mapped_column(
        ForeignKey("lessons.id", ondelete="SET NULL"), nullable=True, index=True
    )
    # "start" | "answer" | "finish"
    action: Mapped[str] = mapped_column(String(16), nullable=False, index=True)
    exercise_key: Mapped[str | None] = mapped_column(String(64), nullable=True)
    word_id: Mapped[int | None] = mapped_column(Integer, nullable=True)

    # What the device sent (the parsed request body, the relevant fields of it).
    payload: Mapped[dict | None] = mapped_column(JSON, nullable=True)

    # What the server did with it.
    accepted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    # Short reason when it was not applied as sent: "слова нет в уроке",
    # "повторный ответ не двигает очки", "слишком быстрый ответ — неверно",
    # "проход не открыт", and so on.
    outcome: Mapped[str | None] = mapped_column(String(255), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )

    user: Mapped["User | None"] = relationship()
