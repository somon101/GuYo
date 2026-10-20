"""The season pass («Пропуск сезона»): XP earned by studying fills a ladder of
levels, each with a free reward and a Premium reward, plus small weekly tasks.

A *definition* -- the levels and the weekly tasks -- is plain JSON:

    {"levels": [{"level": 1, "xp": 80,
                 "free": {"type": "rating_points", "amount": 20},
                 "premium": {"type": "premium_days", "amount": 1}}, ...],
     "tasks":  [{"id": "words", "metric": "word", "target": 5, "xp": 50}, ...]}

It lives on a PassTemplate (any number, one is the default) and a copy of it
on each Season, so editing a template never changes a running season.
"""

from datetime import datetime

from sqlalchemy import JSON, Boolean, DateTime, ForeignKey, Integer, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class PassSettings(Base):
    """Single row (id=1): how much XP each kind of study action is worth."""

    __tablename__ = "pass_settings"

    id: Mapped[int] = mapped_column(primary_key=True)
    xp_word: Mapped[int] = mapped_column(Integer, nullable=False, default=10, server_default="10")
    xp_lesson: Mapped[int] = mapped_column(Integer, nullable=False, default=20, server_default="20")
    xp_review: Mapped[int] = mapped_column(Integer, nullable=False, default=2, server_default="2")
    xp_quest: Mapped[int] = mapped_column(Integer, nullable=False, default=15, server_default="15")
    xp_streak: Mapped[int] = mapped_column(Integer, nullable=False, default=10, server_default="10")
    # Bonus XP for coming back after a break of COMEBACK_DAYS or more.
    # Weekly friend duels: on/off and the winner's bonus XP.
    duels_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    xp_duel_win: Mapped[int] = mapped_column(Integer, nullable=False, default=50, server_default="50")
    # Chest of the day: on/off, the XP range, and the chance (percent) of a streak freeze instead.
    chest_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    chest_xp_min: Mapped[int] = mapped_column(Integer, nullable=False, default=10, server_default="10")
    chest_xp_max: Mapped[int] = mapped_column(Integer, nullable=False, default=40, server_default="40")
    chest_freeze_chance: Mapped[int] = mapped_column(Integer, nullable=False, default=5, server_default="5")
    xp_comeback: Mapped[int] = mapped_column(Integer, nullable=False, default=20, server_default="20")
    xp_daily_goal: Mapped[int] = mapped_column(Integer, nullable=False, default=15, server_default="15")
    # New seasons are created on their own, one per calendar month.
    # The most streak freezes a person can hold at once.
    # The most people in one team.
    team_size: Mapped[int] = mapped_column(Integer, nullable=False, default=5, server_default="5")
    freeze_cap: Mapped[int] = mapped_column(Integer, nullable=False, default=3, server_default="3")
    auto_monthly_seasons: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    # "Reward is waiting" / "season ends soon" / "team goal is close" messages.
    reminders_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")


class PassTemplate(Base):
    __tablename__ = "pass_templates"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    is_default: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    definition: Mapped[dict] = mapped_column(JSON, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class SeasonPass(Base):
    """A season's own copy of a pass definition, taken from a template the
    first time the season needs it."""

    __tablename__ = "season_passes"

    id: Mapped[int] = mapped_column(primary_key=True)
    season_id: Mapped[int] = mapped_column(
        ForeignKey("seasons.id", ondelete="CASCADE"), nullable=False, unique=True, index=True
    )
    template_id: Mapped[int | None] = mapped_column(ForeignKey("pass_templates.id", ondelete="SET NULL"), nullable=True)
    definition: Mapped[dict] = mapped_column(JSON, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class PassXpEvent(Base):
    """One XP award. `dedupe_key` makes every award happen at most once per
    (user, season): the same learned word, lesson or streak day can be
    reported any number of times. `source` is also what weekly tasks count."""

    __tablename__ = "pass_xp_events"
    __table_args__ = (UniqueConstraint("user_id", "season_id", "dedupe_key", name="uq_pass_xp_once"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    season_id: Mapped[int] = mapped_column(ForeignKey("seasons.id", ondelete="CASCADE"), nullable=False, index=True)
    source: Mapped[str] = mapped_column(String(16), nullable=False)
    amount: Mapped[int] = mapped_column(Integer, nullable=False)
    dedupe_key: Mapped[str] = mapped_column(String(120), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True)


class PassClaim(Base):
    """A reward the user took. kind: "free" / "premium" (ref = level) or
    "task" (ref = "<week start date>:<task id>")."""

    __tablename__ = "pass_claims"
    __table_args__ = (UniqueConstraint("user_id", "season_id", "kind", "ref", name="uq_pass_claim_once"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    season_id: Mapped[int] = mapped_column(ForeignKey("seasons.id", ondelete="CASCADE"), nullable=False, index=True)
    kind: Mapped[str] = mapped_column(String(8), nullable=False)
    ref: Mapped[str] = mapped_column(String(64), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class UserCosmetic(Base):
    """A badge or title a person earned (a season-pass reward). Kept for good:
    what was earned in a past season stays in the collection. The badge's
    look comes from `key` (an icon from a fixed set); a title is just its
    text, in up to three languages."""

    __tablename__ = "user_cosmetics"
    __table_args__ = (UniqueConstraint("user_id", "kind", "key", "label", "season_id", name="uq_user_cosmetic_once"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    kind: Mapped[str] = mapped_column(String(8), nullable=False)  # "badge" | "title"
    key: Mapped[str] = mapped_column(String(32), nullable=False, default="", server_default="")
    label: Mapped[str] = mapped_column(String(120), nullable=False)
    label_tg: Mapped[str | None] = mapped_column(String(120), nullable=True)
    label_uz: Mapped[str | None] = mapped_column(String(120), nullable=True)
    season_id: Mapped[int | None] = mapped_column(ForeignKey("seasons.id", ondelete="SET NULL"), nullable=True)
    season_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
