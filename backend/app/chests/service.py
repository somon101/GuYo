"""Chests: granting into the bank, the chest of the day, opening."""

import random as _random
from datetime import datetime, timezone

from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dates import dushanbe_day_start, dushanbe_today
from app.economy.service import grant_diamonds
from app.models.achievement import UserActivityDay
from app.models.chests import ChestSettings, ChestType, UserChest
from app.models.user import User

PRIZE_KINDS = ("diamonds", "freeze", "merge", "points")
_CAP_FIELD = {"diamonds": "max_diamonds", "freeze": "max_freezes", "merge": "max_merges", "points": "max_points"}
SOURCES = ("daily", "pass", "duel", "goal", "streak", "comeback", "admin")


class ChestError(Exception):
    pass


def get_settings(db: Session) -> ChestSettings:
    s = db.get(ChestSettings, 1)
    if s is None:
        s = ChestSettings(id=1)
        db.add(s)
        db.flush()
    return s


def chest_types(db: Session) -> list[ChestType]:
    return db.query(ChestType).order_by(ChestType.sort_order, ChestType.key).all()


def double_active(settings: ChestSettings) -> bool:
    return settings.double_until is not None and settings.double_until > datetime.now(timezone.utc)


def _granted_today(db: Session, user: User) -> int:
    return (
        db.query(func.count(UserChest.id))
        .filter(UserChest.user_id == user.id, UserChest.source != "admin", UserChest.granted_at >= dushanbe_day_start())
        .scalar()
    )


def unopened(db: Session, user: User) -> list[UserChest]:
    return (
        db.query(UserChest)
        .filter(UserChest.user_id == user.id, UserChest.opened_at.is_(None))
        .order_by(UserChest.granted_at, UserChest.id)
        .all()
    )


def grant_chest(
    db: Session, user: User, chest_key: str, source: str, dedupe_key: str | None = None, *, force: bool = False
) -> UserChest | None:
    """Puts a chest in the bank. Returns None when it was already granted for
    this key, or the bank / the per-day cap is full (`force` skips both: used
    for hand-sent chests). Caller owns the commit."""
    if db.get(ChestType, chest_key) is None:
        raise ChestError("Неизвестный сундук")
    settings = get_settings(db)
    if not force:
        if len(unopened(db, user)) >= settings.inventory_max or _granted_today(db, user) >= settings.daily_cap:
            return None
    chest = UserChest(user_id=user.id, chest_key=chest_key, source=source, dedupe_key=dedupe_key)
    try:
        with db.begin_nested():
            db.add(chest)
            db.flush()
    except IntegrityError:
        return None
    _notify(db, user, chest)
    return chest


_TEXTS = {
    "ru": ("Вас ждёт сундук!", "Вам выдан сундук. Откройте его на главном экране."),
    "en": ("A chest is waiting!", "You received a chest. Open it on the home screen."),
    "tg": ("Сундук интизор аст!", "Ба шумо сандуқ дода шуд. Онро дар саҳифаи асосӣ кушоед."),
    "uz": ("Sandiq sizni kutmoqda!", "Sizga sandiq berildi. Uni bosh ekranda oching."),
    "zh": ("有一个宝箱在等你！", "你获得了一个宝箱，请在主页打开。"),
}


def _notify(db: Session, user: User, chest: UserChest) -> None:
    from app.notifications.service import send_notification

    title, body = _TEXTS.get(user.ui_language, _TEXTS["ru"])
    send_notification(db, user, body, title=title, source="chest", dedupe_key=f"chest:{chest.id}")


# ---- chest of the day -------------------------------------------------------

def daily_state(db: Session, user: User) -> dict:
    s = get_settings(db)
    today = dushanbe_today()
    claimed = (
        db.query(UserChest.id).filter_by(user_id=user.id, source="daily", dedupe_key=f"daily:{today.isoformat()}").first()
        is not None
    )
    active = (
        db.query(UserActivityDay.id).filter_by(user_id=user.id, activity_date=today).first() is not None
        if s.daily_requires_activity
        else True
    )
    return {
        "enabled": s.daily_enabled,
        "chest_key": s.daily_chest_key,
        "claimed": claimed,
        "available": s.daily_enabled and active and not claimed,
        "conditions": s.daily_conditions,
    }


def claim_daily(db: Session, user: User) -> UserChest:
    state = daily_state(db, user)
    if not state["enabled"]:
        raise ChestError("Сундук дня сейчас недоступен")
    if state["claimed"]:
        raise ChestError("Сундук дня уже получен сегодня")
    if not state["available"]:
        raise ChestError("Сундук дня откроется после занятия сегодня")
    chest = grant_chest(db, user, state["chest_key"], "daily", f"daily:{dushanbe_today().isoformat()}")
    if chest is None:
        raise ChestError("Копилка сундуков заполнена — откройте накопленные")
    return chest


# ---- opening ---------------------------------------------------------------

def _roll_amount(cap: int, rng, pity: bool) -> tuple[int, bool]:
    if pity and cap > 1:
        amount = rng.randint((cap + 1) // 2, cap)
    else:
        amount = rng.randint(1, cap)
    return amount, amount * 2 <= cap


def _pity_due(db: Session, user: User, settings: ChestSettings) -> bool:
    n = settings.pity_after
    if n <= 0:
        return False
    last = (
        db.query(UserChest.low_roll)
        .filter(UserChest.user_id == user.id, UserChest.opened_at.is_not(None))
        .order_by(UserChest.opened_at.desc(), UserChest.id.desc())
        .limit(n)
        .all()
    )
    return len(last) == n and all(r[0] for r in last)


def open_chest(db: Session, user: User, chest_id: int, rng: _random.Random | None = None) -> UserChest:
    rng = rng or _random.SystemRandom()
    chest = (
        db.query(UserChest)
        .filter(UserChest.id == chest_id, UserChest.user_id == user.id)
        .with_for_update()
        .first()
    )
    if chest is None:
        raise ChestError("Сундук не найден")
    if chest.opened_at is not None:
        raise ChestError("Этот сундук уже открыт")
    ctype = db.get(ChestType, chest.chest_key)
    options = [k for k in PRIZE_KINDS if getattr(ctype, _CAP_FIELD[k]) > 0]
    if not options:
        raise ChestError("В этом сундуке нет призов")
    settings = get_settings(db)
    kind = rng.choice(options)
    amount, low = _roll_amount(getattr(ctype, _CAP_FIELD[kind]), rng, _pity_due(db, user, settings))
    if double_active(settings):
        amount *= 2
    chest.prize_kind, chest.prize_amount, chest.low_roll = kind, amount, low
    chest.opened_at = datetime.now(timezone.utc)
    award_prize(db, user, kind, amount, f"chest:{chest.id}")
    db.flush()
    return chest


def open_many(
    db: Session, user: User, chest_key: str, count: int, rng: _random.Random | None = None
) -> list[UserChest]:
    """Opens `count` (1, 5 or 10) chests of ONE kind, oldest first. All or nothing:
    fewer than `count` in the bank is refused."""
    if count not in (1, 5, 10):
        raise ChestError("Можно открыть 1, 5 или 10 сундуков")
    ids = [c.id for c in unopened(db, user) if c.chest_key == chest_key]
    if len(ids) < count:
        raise ChestError("Столько сундуков этого вида нет")
    return [open_chest(db, user, i, rng) for i in ids[:count]]


def award_prize(db: Session, user: User, kind: str, amount: int, reference: str) -> None:
    if kind == "diamonds":
        grant_diamonds(db, user, amount, "chest", reference)
    elif kind == "freeze":
        user.streak_freezes = (user.streak_freezes or 0) + amount
    elif kind == "merge":
        user.streak_merge_items = (user.streak_merge_items or 0) + amount
    elif kind == "points":
        from app.rating import grant_rating_points

        grant_rating_points(db, user, amount)
    else:
        raise ChestError("Неизвестный приз")


# ---- state / stats ----------------------------------------------------------

def user_state(db: Session, user: User) -> dict:
    s = get_settings(db)
    return {
        "types": [type_out(t) for t in chest_types(db)],
        "chests": [{"id": c.id, "chest_key": c.chest_key, "source": c.source} for c in unopened(db, user)],
        "daily": daily_state(db, user),
        "double": double_active(s),
        "inventory_max": s.inventory_max,
    }


def type_out(t: ChestType) -> dict:
    return {
        "key": t.key, "name": t.name, "color": t.color, "max_diamonds": t.max_diamonds,
        "max_freezes": t.max_freezes, "max_merges": t.max_merges, "max_points": t.max_points,
    }


def stats(db: Session, days: int = 30) -> dict:
    from datetime import timedelta

    since = datetime.now(timezone.utc) - timedelta(days=days)
    rows = (
        db.query(UserChest.chest_key, UserChest.source, func.count(UserChest.id))
        .filter(UserChest.granted_at >= since)
        .group_by(UserChest.chest_key, UserChest.source)
        .all()
    )
    prizes = (
        db.query(UserChest.prize_kind, func.count(UserChest.id), func.coalesce(func.sum(UserChest.prize_amount), 0))
        .filter(UserChest.opened_at >= since)
        .group_by(UserChest.prize_kind)
        .all()
    )
    return {
        "days": days,
        "granted": [{"chest_key": k, "source": s, "count": n} for k, s, n in rows],
        "prizes": [{"kind": k, "opened": n, "total": int(t)} for k, n, t in prizes],
    }
