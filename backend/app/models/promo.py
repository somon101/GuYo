"""Promo codes: two ways to get Premium days without paying.

- PromoCode: a word the admin makes up ("GUYO2026") worth a fixed number
  of days, optionally with an expiry date and a cap on activations.
- PromoLink: a link to one of GuYo's own videos (YouTube, Instagram,
  TikTok, ...). The video tells viewers to paste its link into the app.
  How much a link is worth depends on the USER, not the link: their very
  first link gives PremiumSettings.promo_link_first_days, and every link
  after that gives the link's own repeat_days, or
  PremiumSettings.promo_link_repeat_days when the link has none.

Every activation goes through app/promo/service.py's redeem_promo, which
turns it into an ordinary PremiumGrant (source "promo") through
grant_premium -- a promo is one more way to get a grant, never a second
kind of Premium.

Links are matched by `normalized_key`, not by the text as pasted: the
same video shared as youtu.be/ID, youtube.com/watch?v=ID&si=... or
m.youtube.com/... is one link (see app/promo/links.py).
"""

from datetime import datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class PromoCode(Base):
    """`code` is stored upper-cased and trimmed, and the user's input is
    normalized the same way before lookup -- "guyo2026" and "GUYO2026"
    are one code.

    `expires_at` and `max_activations` are both optional; NULL means no
    expiry / no cap. Each user can activate a given code once, whatever
    the cap."""

    __tablename__ = "promo_codes"
    __table_args__ = (
        CheckConstraint("days > 0", name="ck_promo_code_days_positive"),
        CheckConstraint("max_activations IS NULL OR max_activations > 0", name="ck_promo_code_max_positive"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(String(40), unique=True, index=True, nullable=False)
    days: Mapped[int] = mapped_column(Integer, nullable=False)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    max_activations: Mapped[int | None] = mapped_column(Integer, nullable=True)
    # The admin's own reminder of what this code is for ("стрим 26.09").
    # Never shown to users.
    note: Mapped[str | None] = mapped_column(String(300), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class PromoLink(Base):
    """One video link. `url` is kept exactly as the admin entered it, for
    display; `normalized_key` is what a user's pasted link is matched
    against, and is unique so the same video can't be added twice under
    two spellings.

    `repeat_days` is this link's own reward for a user who has ALREADY
    activated some other link before; NULL means "use the global
    PremiumSettings.promo_link_repeat_days". A user's FIRST link always
    gives PremiumSettings.promo_link_first_days, whichever link it is."""

    __tablename__ = "promo_links"
    __table_args__ = (CheckConstraint("repeat_days IS NULL OR repeat_days > 0", name="ck_promo_link_days_positive"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    url: Mapped[str] = mapped_column(String(1000), nullable=False)
    normalized_key: Mapped[str] = mapped_column(String(1000), unique=True, index=True, nullable=False)
    title: Mapped[str | None] = mapped_column(String(200), nullable=True)
    repeat_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class PromoActivation(Base):
    """One user activating one code or one link -- exactly one of the two
    is set. UNIQUE(user_id, promo_code_id) and UNIQUE(user_id,
    promo_link_id) are what actually guarantee "once per user" (NULLs
    never collide, so the unused column doesn't get in the way).

    `days` is what this activation actually gave, frozen at the time --
    editing a code or the link settings later never rewrites history.
    `grant_id` points at the PremiumGrant it produced.

    Codes and links that have been activated are never deleted (disable
    them instead), so both foreign keys can simply RESTRICT."""

    __tablename__ = "promo_activations"
    __table_args__ = (
        UniqueConstraint("user_id", "promo_code_id", name="uq_promo_activation_user_code"),
        UniqueConstraint("user_id", "promo_link_id", name="uq_promo_activation_user_link"),
        CheckConstraint(
            "(promo_code_id IS NULL) <> (promo_link_id IS NULL)", name="ck_promo_activation_exactly_one"
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    promo_code_id: Mapped[int | None] = mapped_column(
        ForeignKey("promo_codes.id", ondelete="RESTRICT"), nullable=True, index=True
    )
    promo_link_id: Mapped[int | None] = mapped_column(
        ForeignKey("promo_links.id", ondelete="RESTRICT"), nullable=True, index=True
    )
    days: Mapped[int] = mapped_column(Integer, nullable=False)
    # True for the user's first-ever link -- the one that got the bigger
    # first-time reward.
    is_first_link: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    grant_id: Mapped[int | None] = mapped_column(ForeignKey("premium_grants.id", ondelete="SET NULL"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True)
