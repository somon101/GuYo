"""The «Лента»: automatic cards about good things that happened to people, likes and ready-made comments."""

from datetime import datetime

from sqlalchemy import JSON, Boolean, DateTime, ForeignKey, Index, Integer, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class FeedCard(Base):
    """One card. Nobody writes it: the app's own events create it (a streak, learned words, an
    achievement, a duel won). `data` holds the facts the card is made of; the words are put together
    on the phone in the reader's language."""

    __tablename__ = "feed_cards"
    __table_args__ = (
        UniqueConstraint("dedupe_key", name="uq_feed_card_once"),
        Index("ix_feed_cards_created", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    kind: Mapped[str] = mapped_column(String(16), nullable=False)  # streak | words | achievement | rank | duel
    data: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    dedupe_key: Mapped[str] = mapped_column(String(120), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    # Reach, as on Instagram: a card is first shown to a small group of strangers; while that group
    # reacts well the group grows, when interest drops it stops. Friends always see it.
    views: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    reach: Mapped[int] = mapped_column(Integer, nullable=False, default=30, server_default="30")
    likes: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    comments: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")


class FeedLike(Base):
    __tablename__ = "feed_likes"
    __table_args__ = (UniqueConstraint("card_id", "user_id", name="uq_feed_like_once"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    card_id: Mapped[int] = mapped_column(ForeignKey("feed_cards.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class FeedComment(Base):
    """A comment is one ready-made phrase (nobody types their own); one per person under a card."""

    __tablename__ = "feed_comments"
    __table_args__ = (UniqueConstraint("card_id", "user_id", name="uq_feed_comment_once"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    card_id: Mapped[int] = mapped_column(ForeignKey("feed_cards.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    phrase: Mapped[str] = mapped_column(String(64), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class FeedSeen(Base):
    """A person saw a card (counted once): the author's number of views and the reach rule use it.
    A hidden card is a row with `hidden`."""

    __tablename__ = "feed_seen"
    __table_args__ = (UniqueConstraint("card_id", "user_id", name="uq_feed_seen_once"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    card_id: Mapped[int] = mapped_column(ForeignKey("feed_cards.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    hidden: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
