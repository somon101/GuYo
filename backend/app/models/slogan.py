"""Greeting slogans: the one line under "Привет, {имя}" on Главная.

A definition table an admin curates, plus a record of which slogan each
user was given on which day. Deliberately two tables and not one: the
slogan text belongs to the admin and is edited freely, while "what this
user saw today" is per-user history that must not change when the text is
reworded.
"""

from datetime import date, datetime

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Integer, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Slogan(Base):
    """One greeting line an admin wrote.

    Same "definition row an admin curates" shape as Quest and Rank: an
    `enabled` flag rather than deletion for anything already shown, and an
    explicit `order` so the admin's list has a stable, draggable sequence.
    Disabled slogans are never handed to a user but stay editable.
    """

    __tablename__ = "slogans"

    id: Mapped[int] = mapped_column(primary_key=True)
    text: Mapped[str] = mapped_column(String(255), nullable=False)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class UserDailySlogan(Base):
    """Which slogan one user was given on one day.

    This is what makes the greeting hold still: the pick happens once per
    day and is then read back, so the line does not change while the user
    is looking at it, and a new day genuinely brings a different one.

    `shown_date` is the server's own Asia/Dushanbe date -- the SAME day
    boundary quests already reset on (app/core/dates.py), so the app never
    holds two different ideas of when a new day starts.

    UNIQUE(user_id, shown_date) is what actually enforces "one slogan per
    user per day" at the database level, exactly as
    UserQuestWordDay's own unique constraint does for its rule. The
    slogan_id cascade means removing a slogan simply drops the pins that
    pointed at it, and those users are given a fresh one.
    """

    __tablename__ = "user_daily_slogans"
    __table_args__ = (UniqueConstraint("user_id", "shown_date", name="uq_user_daily_slogan_once"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    slogan_id: Mapped[int] = mapped_column(ForeignKey("slogans.id", ondelete="CASCADE"), nullable=False, index=True)
    shown_date: Mapped[date] = mapped_column(Date, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
