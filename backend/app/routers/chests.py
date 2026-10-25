"""Chests: the person's bank + the chest of the day; admin: types, settings, sending, stats."""

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.chests import boosters, rewards, service
from app.chests.service import ChestError
from app.core.deps import get_current_admin, get_current_user
from app.database import get_db
from app.models.chests import ChestType
from app.models.user import User

router = APIRouter(prefix="/chests", tags=["chests"])
boosters_router = APIRouter(prefix="/boosters", tags=["boosters"])
admin_router = APIRouter(prefix="/admin/chests", tags=["admin-chests"])


def _conflict(e: ChestError) -> HTTPException:
    return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(e))


@router.get("")
def my_chests(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    try:
        service.roll_all(db, user)  # every chest in the bank carries its sealed prize
    except ChestError:
        db.rollback()
    db.commit()
    return service.user_state(db, user)


@router.post("/daily/claim")
def claim_daily(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    try:
        service.claim_daily(db, user)
        service.roll_all(db, user)
    except ChestError as e:
        db.rollback()
        raise _conflict(e) from None
    db.commit()
    return service.user_state(db, user)


@router.post("/{chest_id}/open")
def open_one(chest_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    try:
        chest = service.open_chest(db, user, chest_id)
    except ChestError as e:
        db.rollback()
        raise _conflict(e) from None
    db.commit()
    db.refresh(user)
    return {
        "chest_key": chest.chest_key, "kind": chest.prize_kind, "amount": chest.prize_amount,
        "diamonds": user.diamonds_balance, "state": service.user_state(db, user),
    }


class OpenManyIn(BaseModel):
    chest_key: str
    count: int = Field(ge=1, le=10)


@router.post("/open-many")
def open_many(payload: OpenManyIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    try:
        opened = service.open_many(db, user, payload.chest_key, payload.count)
    except ChestError as e:
        db.rollback()
        raise _conflict(e) from None
    db.commit()
    db.refresh(user)
    return {
        "chest_key": payload.chest_key,
        "prizes": [{"kind": c.prize_kind, "amount": c.prize_amount, "doubled": c.doubled} for c in opened],
        "diamonds": user.diamonds_balance,
        "state": service.user_state(db, user),
    }


class OpenedItem(BaseModel):
    id: int
    opened_at: datetime | None = None  # when the app opened it (offline opens arrive later)


class OpenIdsIn(BaseModel):
    ids: list[int] = Field(default_factory=list, max_length=10)
    items: list[OpenedItem] = Field(default_factory=list, max_length=10)


@router.post("/open-ids")
def open_ids(payload: OpenIdsIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Tells the server which chests the app has just opened (it showed the prizes at once).
    Idempotent: safe to repeat after a dropped connection."""
    try:
        ids = payload.ids + [i.id for i in payload.items if i.id not in payload.ids]
        if not ids:
            raise ChestError("Не указаны сундуки")
        opened = service.open_ids(db, user, ids, {i.id: i.opened_at for i in payload.items if i.opened_at})
        service.roll_all(db, user)
    except ChestError as e:
        db.rollback()
        raise _conflict(e) from None
    db.commit()
    db.refresh(user)
    return {
        "prizes": [{"id": c.id, "kind": c.prize_kind, "amount": c.prize_amount, "doubled": c.doubled} for c in opened],
        "diamonds": user.diamonds_balance,
        "state": service.user_state(db, user),
    }


class ActivateIn(BaseModel):
    minutes: int = Field(ge=1, le=10_080)


@boosters_router.get("")
def my_boosters(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return boosters.state(db, user)


@boosters_router.post("/activate")
def activate_booster(payload: ActivateIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    try:
        boosters.activate(db, user, payload.minutes)
    except boosters.BoosterError as e:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(e)) from None
    db.commit()
    return boosters.state(db, user)


# ---- admin ------------------------------------------------------------------

class TypeIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    color: str = Field(pattern=r"^#[0-9a-fA-F]{6}$")
    max_diamonds: int = Field(ge=0, le=1_000_000)
    max_freezes: int = Field(ge=0, le=1000)
    max_merges: int = Field(ge=0, le=1000)
    max_points: int = Field(ge=0, le=1_000_000)
    booster_minutes: int = Field(default=0, ge=0, le=10_080)


class SettingsIn(BaseModel):
    daily_enabled: bool
    daily_chest_key: str
    daily_requires_activity: bool
    daily_conditions: str = Field(max_length=2000)
    inventory_max: int = Field(ge=1, le=100)
    daily_cap: int = Field(ge=1, le=100)
    pity_after: int = Field(ge=0, le=100)
    double_hours: int | None = Field(default=None, ge=0, le=24 * 30)  # start/extend now; 0 = stop


class SendIn(BaseModel):
    user: str = Field(min_length=1, max_length=120)
    chest_key: str
    count: int = Field(default=1, ge=1, le=10)


def _settings_out(db: Session) -> dict:
    s = service.get_settings(db)
    return {
        "daily_enabled": s.daily_enabled, "daily_chest_key": s.daily_chest_key,
        "daily_requires_activity": s.daily_requires_activity, "daily_conditions": s.daily_conditions,
        "inventory_max": s.inventory_max, "daily_cap": s.daily_cap, "pity_after": s.pity_after,
        "double_until": s.double_until.isoformat() if service.double_active(s) else None,
    }


@admin_router.get("")
def admin_overview(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    db.commit()  # persists the lazily created settings row
    return {"types": [service.type_out(t) for t in service.chest_types(db)], "settings": _settings_out(db),
            "stats": service.stats(db)}


@admin_router.put("/types/{key}")
def update_type(key: str, payload: TypeIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    t = db.get(ChestType, key)
    if t is None:
        raise HTTPException(status_code=404, detail="Сундук не найден")
    if not (payload.max_diamonds or payload.max_freezes or payload.max_merges or payload.max_points or payload.booster_minutes):
        raise HTTPException(status_code=422, detail="В сундуке должен быть хотя бы один приз")
    for k, v in payload.model_dump().items():
        setattr(t, k, v)
    db.commit()
    return service.type_out(t)


@admin_router.put("/settings")
def update_settings(payload: SettingsIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    if db.get(ChestType, payload.daily_chest_key) is None:
        raise HTTPException(status_code=422, detail="Неизвестный сундук")
    s = service.get_settings(db)
    data = payload.model_dump(exclude={"double_hours"})
    for k, v in data.items():
        setattr(s, k, v)
    if payload.double_hours is not None:
        s.double_until = (
            datetime.now(timezone.utc) + timedelta(hours=payload.double_hours) if payload.double_hours else None
        )
    db.commit()
    return _settings_out(db)


@admin_router.post("/send")
def send_chest(payload: SendIn, db: Session = Depends(get_db), admin=Depends(get_current_admin)):
    """Hand-sends chests (repeatable, ignores the bank and daily limits) so an
    admin can see where and how they appear."""
    import uuid

    key = payload.user.strip()
    query = db.query(User).filter(User.deleted_at.is_(None))
    user = query.filter(User.public_id == int(key)).first() if key.isdigit() else None
    if user is None:
        user = query.filter(func.lower(User.login) == key.lower()).first()
    if user is None:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    try:
        for _ in range(payload.count):
            service.grant_chest(db, user, payload.chest_key, "admin", f"admin:{admin.id}:{uuid.uuid4().hex}", force=True)
    except ChestError as e:
        db.rollback()
        raise HTTPException(status_code=422, detail=str(e)) from None
    db.commit()
    return {"login": user.login, "chest_key": payload.chest_key, "count": payload.count,
            "bank": len(service.unopened(db, user))}


@admin_router.get("/rewards")
def get_rewards(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    return rewards.all_rules(db)


@admin_router.put("/rewards")
def put_rewards(payload: dict, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    try:
        out = rewards.save_rules(db, payload)
    except (ChestError, ValueError, TypeError, AttributeError) as e:
        db.rollback()
        raise HTTPException(status_code=422, detail=str(e) or "Неверные данные") from None
    db.commit()
    return out


class SendBoosterIn(BaseModel):
    user: str = Field(min_length=1, max_length=120)
    minutes: int = Field(ge=1, le=10_080)
    count: int = Field(default=1, ge=1, le=20)


@admin_router.post("/send-booster")
def send_booster(payload: SendBoosterIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    key = payload.user.strip()
    query = db.query(User).filter(User.deleted_at.is_(None))
    user = query.filter(User.public_id == int(key)).first() if key.isdigit() else None
    if user is None:
        user = query.filter(func.lower(User.login) == key.lower()).first()
    if user is None:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    boosters.add_booster(db, user, payload.minutes, payload.count)
    db.commit()
    return {"login": user.login, "minutes": payload.minutes, "count": payload.count}
