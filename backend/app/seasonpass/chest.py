"""The chest of the day: opens once a day, after the first study of that day."""

import random as _random

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.achievements.streak import active_today
from app.core.dates import dushanbe_today
from app.models.chest import DailyChest
from app.models.user import User
from app.seasonpass.service import PassError, award_xp, get_pass_settings


class ChestError(PassError):
    pass


def today_chest(db: Session, user: User) -> DailyChest | None:
    return db.query(DailyChest).filter_by(user_id=user.id, chest_date=dushanbe_today()).first()


def state(db: Session, user: User) -> dict:
    settings = get_pass_settings(db)
    opened = today_chest(db, user)
    return {
        "enabled": settings.chest_enabled,
        "available": settings.chest_enabled and opened is None and active_today(db, user),
        "opened": None if opened is None else {"kind": opened.kind, "amount": opened.amount},
    }


def open_chest(db: Session, user: User, rng: _random.Random | None = None) -> DailyChest:
    rng = rng or _random
    settings = get_pass_settings(db)
    if not settings.chest_enabled:
        raise ChestError("Сундук сейчас недоступен")
    if today_chest(db, user) is not None:
        raise ChestError("Сегодняшний сундук уже открыт")
    if not active_today(db, user):
        raise ChestError("Сундук откроется после первого занятия сегодня")
    kind, amount = "xp", rng.randint(min(settings.chest_xp_min, settings.chest_xp_max), max(settings.chest_xp_min, settings.chest_xp_max))
    if rng.randint(1, 100) <= settings.chest_freeze_chance and (user.streak_freezes or 0) < settings.freeze_cap:
        kind, amount = "freeze", 1
    chest = DailyChest(user_id=user.id, chest_date=dushanbe_today(), kind=kind, amount=amount)
    try:
        with db.begin_nested():
            db.add(chest)
            db.flush()
    except IntegrityError:
        raise ChestError("Сегодняшний сундук уже открыт") from None
    if kind == "freeze":
        user.streak_freezes = (user.streak_freezes or 0) + 1
    else:
        award_xp(db, user, "chest", f"chest:{chest.chest_date.isoformat()}", amount)
    return chest
