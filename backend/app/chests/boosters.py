"""The "x2" ticket: held in the inventory, switched on by hand, doubles the prizes of
chests opened while it runs. Nothing else is doubled."""

from datetime import datetime, timedelta, timezone

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.chests import BoosterUse, UserBooster
from app.models.user import User

STANDARD_MINUTES = (30, 60, 1440)


class BoosterError(Exception):
    pass


def _now() -> datetime:
    return datetime.now(timezone.utc)


def add_booster(db: Session, user: User, minutes: int, qty: int = 1) -> None:
    row = db.query(UserBooster).filter_by(user_id=user.id, minutes=minutes).with_for_update().first()
    if row is None:
        db.add(UserBooster(user_id=user.id, minutes=minutes, qty=qty))
    else:
        row.qty += qty
    db.flush()


def active_until(db: Session, user: User) -> datetime | None:
    until = db.query(func.max(BoosterUse.ends_at)).filter(BoosterUse.user_id == user.id).scalar()
    return until if until is not None and until > _now() else None


def active_at(db: Session, user: User, when: datetime) -> bool:
    """Was a ticket running at `when`? (A chest opened offline is judged by the moment it was opened.)"""
    return (
        db.query(BoosterUse.id)
        .filter(BoosterUse.user_id == user.id, BoosterUse.starts_at <= when, BoosterUse.ends_at > when)
        .first()
        is not None
    )


def clamp_time(value: datetime | None) -> datetime:
    """The moment an offline-opened chest claims to have been opened, kept inside sane bounds."""
    now = _now()
    if value is None:
        return now
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return max(now - timedelta(days=3), min(value, now))


def activate(db: Session, user: User, minutes: int) -> datetime:
    row = db.query(UserBooster).filter_by(user_id=user.id, minutes=minutes).with_for_update().first()
    if row is None or row.qty < 1:
        raise BoosterError("Такого билета нет")
    row.qty -= 1
    start = max(_now(), active_until(db, user) or _now())  # a second ticket adds its time to the running one
    end = start + timedelta(minutes=minutes)
    db.add(BoosterUse(user_id=user.id, starts_at=start, ends_at=end))
    db.flush()
    return end


def total_qty(db: Session, user: User) -> int:
    return int(db.query(func.coalesce(func.sum(UserBooster.qty), 0)).filter(UserBooster.user_id == user.id).scalar() or 0)


def state(db: Session, user: User) -> dict:
    held = {r.minutes: r.qty for r in db.query(UserBooster).filter_by(user_id=user.id)}
    minutes = sorted(set(STANDARD_MINUTES) | {m for m, q in held.items() if q > 0})
    until = active_until(db, user)
    return {
        "items": [{"minutes": m, "qty": held.get(m, 0)} for m in minutes],
        "active_until": until.isoformat() if until else None,
        "seconds_left": int((until - _now()).total_seconds()) if until else 0,
    }
