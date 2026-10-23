"""The daily gift chest (legacy /chest API, backed by the gift ledger)."""

import random as _random

from sqlalchemy.orm import Session

from app.core.dates import dushanbe_today
from app.economy.service import EconomyError, gift_state, open_gift
from app.models.economy import GiftDefinition, GiftOpen
from app.models.user import User
from app.seasonpass.service import PassError, get_pass_settings


class ChestError(PassError):
    pass


def daily_gift(db: Session) -> GiftDefinition:
    gift = db.query(GiftDefinition).filter_by(key="daily-chest").first()
    if gift is None:
        gift = GiftDefinition(
            key="daily-chest", name="Подарок дня", description="Откройте после занятия и получите бриллианты",
            icon_key="chest", reward_min=5, reward_max=25, cooldown_days=1, requires_activity=True,
            enabled=True, sort_order=0,
        )
        db.add(gift)
        db.flush()
    return gift


def today_chest(db: Session, user: User) -> GiftOpen | None:
    gift = daily_gift(db)
    return db.query(GiftOpen).filter_by(user_id=user.id, gift_id=gift.id, opened_on=dushanbe_today()).first()


def state(db: Session, user: User) -> dict:
    settings = get_pass_settings(db)
    gift = daily_gift(db)
    opened = today_chest(db, user)
    availability = gift_state(db, user, gift)
    return {
        "enabled": settings.chest_enabled and gift.enabled,
        "available": settings.chest_enabled and availability["available"],
        "opened": None if opened is None else {"kind": opened.kind, "amount": opened.amount},
    }


def open_chest(db: Session, user: User, rng: _random.Random | None = None) -> GiftOpen:
    settings = get_pass_settings(db)
    if not settings.chest_enabled:
        raise ChestError("Сундук сейчас недоступен")
    gift = daily_gift(db)
    try:
        return open_gift(db, user, gift, rng, allow_freeze=True)
    except EconomyError as e:
        raise ChestError(str(e)) from None
