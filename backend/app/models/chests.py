"""Chests: four kinds (wood, silver, purple, gold), a per-user bank of unopened
ones, and the single settings row for the chest of the day."""

from datetime import date, datetime

from sqlalchemy import JSON, Boolean, Date, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class ChestType(Base):
    """One of the four chests. A zero ceiling means that prize is not in the chest."""

    __tablename__ = "chest_types"

    key: Mapped[str] = mapped_column(String(16), primary_key=True)  # wood | silver | purple | gold
    name: Mapped[str] = mapped_column(String(80), nullable=False)
    color: Mapped[str] = mapped_column(String(9), nullable=False, default="#9b6b3a", server_default="#9b6b3a")
    max_diamonds: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    max_freezes: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    max_merges: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    max_points: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    # Minutes of the "x2" ticket this chest can hold as a prize (0 = it never does).
    booster_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")


class UserChest(Base):
    """A chest given to a person. `opened_at` empty = still in the bank."""

    __tablename__ = "user_chests"
    __table_args__ = (UniqueConstraint("user_id", "dedupe_key", name="uq_user_chest_dedupe"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    chest_key: Mapped[str] = mapped_column(String(16), nullable=False)
    source: Mapped[str] = mapped_column(String(24), nullable=False)  # daily | pass | duel | goal | streak | comeback | admin
    dedupe_key: Mapped[str | None] = mapped_column(String(160), nullable=True)
    granted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False, index=True)
    opened_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    prize_kind: Mapped[str | None] = mapped_column(String(16), nullable=True)  # diamonds | freeze | merge | points
    prize_amount: Mapped[int | None] = mapped_column(Integer, nullable=True)
    low_roll: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    doubled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")


class ChestSettings(Base):
    """Single row (id=1)."""

    __tablename__ = "chest_settings"

    id: Mapped[int] = mapped_column(primary_key=True)
    daily_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    daily_chest_key: Mapped[str] = mapped_column(String(16), nullable=False, default="wood", server_default="wood")
    daily_requires_activity: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    daily_conditions: Mapped[str] = mapped_column(
        Text, nullable=False, default="Сундук дня даётся один раз в сутки после первого занятия.",
        server_default="Сундук дня даётся один раз в сутки после первого занятия.",
    )
    inventory_max: Mapped[int] = mapped_column(Integer, nullable=False, default=10, server_default="10")
    daily_cap: Mapped[int] = mapped_column(Integer, nullable=False, default=10, server_default="10")  # per person per day, admin gifts excluded
    pity_after: Mapped[int] = mapped_column(Integer, nullable=False, default=5, server_default="5")  # 0 = off
    double_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class RewardRule(Base):
    """Admin-editable rewards per event. `data` is a list of reward specs, or,
    for the daily goal, a list of {words, rewards} tiers."""

    __tablename__ = "reward_rules"

    key: Mapped[str] = mapped_column(String(32), primary_key=True)
    data: Mapped[list] = mapped_column(JSON, nullable=False)


class DailyGoalClaim(Base):
    """One paid daily-goal tier per person per Dushanbe day."""

    __tablename__ = "daily_goal_claims"
    __table_args__ = (UniqueConstraint("user_id", "day", "words", name="uq_daily_goal_claim"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    day: Mapped[date] = mapped_column(Date, nullable=False)
    words: Mapped[int] = mapped_column(Integer, nullable=False)
    # Earned when the goal is filled; paid only when the person presses «Получить».
    claimed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    notified: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")


class RewardMarker(Base):
    """Once-only marker for rewards that have no ledger of their own (rating points)."""

    __tablename__ = "reward_markers"
    __table_args__ = (UniqueConstraint("user_id", "key", name="uq_reward_marker"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    key: Mapped[str] = mapped_column(String(160), nullable=False)


class UserBooster(Base):
    """"x2" tickets a person holds, by duration. They are switched on by hand."""

    __tablename__ = "user_boosters"
    __table_args__ = (UniqueConstraint("user_id", "minutes", name="uq_user_booster_minutes"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    qty: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")


class BoosterUse(Base):
    """One switched-on ticket: the prizes of chests opened between starts_at and ends_at are doubled."""

    __tablename__ = "booster_uses"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ends_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
