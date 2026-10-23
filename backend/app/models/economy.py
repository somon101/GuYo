"""Virtual diamonds, the catalog of gifts, and the in-app shop."""

from datetime import date, datetime

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class DiamondTransaction(Base):
    """Append-only wallet ledger. ``amount`` is positive for a grant and
    negative for a purchase; ``reference`` makes every source idempotent."""

    __tablename__ = "diamond_transactions"
    __table_args__ = (UniqueConstraint("user_id", "reference", name="uq_diamond_transaction_reference"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    amount: Mapped[int] = mapped_column(Integer, nullable=False)
    source: Mapped[str] = mapped_column(String(32), nullable=False)
    reference: Mapped[str] = mapped_column(String(160), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class ShopProduct(Base):
    """An admin-configured shop item. Supported types are intentionally
    plain strings so future item types do not require a database enum."""

    __tablename__ = "shop_products"

    id: Mapped[int] = mapped_column(primary_key=True)
    sku: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False, default="", server_default="")
    item_type: Mapped[str] = mapped_column(String(32), nullable=False)  # streak_freeze | streak_merge
    quantity: Mapped[int] = mapped_column(Integer, nullable=False)
    price_diamonds: Mapped[int] = mapped_column(Integer, nullable=False)
    icon_key: Mapped[str] = mapped_column(String(32), nullable=False, default="gift", server_default="gift")
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)


class GiftDefinition(Base):
    """An admin-configured gift that can award a random amount of diamonds."""

    __tablename__ = "gift_definitions"

    id: Mapped[int] = mapped_column(primary_key=True)
    key: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False, default="", server_default="")
    icon_key: Mapped[str] = mapped_column(String(32), nullable=False, default="gift", server_default="gift")
    reward_min: Mapped[int] = mapped_column(Integer, nullable=False)
    reward_max: Mapped[int] = mapped_column(Integer, nullable=False)
    cooldown_days: Mapped[int] = mapped_column(Integer, nullable=False, default=1, server_default="1")
    requires_activity: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)


class GiftOpen(Base):
    """A gift opening and immutable reward snapshot."""

    __tablename__ = "gift_opens"
    __table_args__ = (UniqueConstraint("user_id", "gift_id", "opened_on", name="uq_gift_open_per_day"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    gift_id: Mapped[int] = mapped_column(ForeignKey("gift_definitions.id", ondelete="CASCADE"), nullable=False, index=True)
    opened_on: Mapped[date] = mapped_column(Date, nullable=False)
    kind: Mapped[str] = mapped_column(String(24), nullable=False)  # diamonds | freeze
    amount: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
