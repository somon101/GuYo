"""The learner's season pass: the ladder, claiming rewards, weekly tasks."""

from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.database import get_db
from app.models.user import User
from app.seasonpass import PassError, claim_level, claim_task, user_state
from app.seasonpass.cosmetics import CosmeticError, collection, equip

router = APIRouter(prefix="/season-pass", tags=["season-pass"])


class RewardOut(BaseModel):
    type: str
    amount: int
    key: str | None = None
    text: str | None = None
    claimed: bool
    claimable: bool
    locked_by_premium: bool = False


class LevelOut(BaseModel):
    level: int
    xp: int
    free: RewardOut | None
    premium: RewardOut | None


class TaskOut(BaseModel):
    id: str
    metric: str
    target: int
    xp: int
    progress: int
    claimed: bool
    claimable: bool


class WeekOut(BaseModel):
    starts_on: date
    ends_at: datetime
    tasks: list[TaskOut]


class PassOut(BaseModel):
    season_id: int
    season_name: str
    season_name_tg: str | None
    season_name_uz: str | None
    starts_at: datetime
    ends_at: datetime | None
    xp: int
    level: int
    xp_into_level: int
    xp_for_next: int | None
    is_premium: bool
    premium_enabled: bool
    streak_freezes: int = 0
    levels: list[LevelOut]
    week: WeekOut


class ClaimLevelIn(BaseModel):
    level: int
    track: str


class CosmeticOut(BaseModel):
    id: int
    kind: str
    key: str
    label: str
    season_name: str | None


class CollectionOut(BaseModel):
    badges: list[CosmeticOut]
    titles: list[CosmeticOut]
    equipped_badge_id: int | None
    equipped_title_id: int | None


class EquipIn(BaseModel):
    badge_id: int | None = None
    title_id: int | None = None


class ClaimTaskIn(BaseModel):
    task_id: str


def _refuse(e: PassError) -> HTTPException:
    return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(e))


@router.get("", response_model=PassOut)
def get_pass(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    state = user_state(db, user)
    db.commit()
    if state is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Сейчас нет активного сезона")
    return state


@router.get("/cosmetics", response_model=CollectionOut)
def get_collection(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return collection(db, user)


@router.put("/cosmetics/equip", response_model=CollectionOut)
def equip_cosmetics(payload: EquipIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    try:
        equip(db, user, payload.badge_id, payload.title_id)
    except CosmeticError as e:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(e)) from None
    db.commit()
    return collection(db, user)


@router.post("/claim", response_model=PassOut)
def claim(payload: ClaimLevelIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    try:
        claim_level(db, user, payload.level, payload.track)
    except PassError as e:
        db.rollback()
        raise _refuse(e) from None
    db.commit()
    return user_state(db, user)


@router.post("/tasks/claim", response_model=PassOut)
def claim_weekly_task(payload: ClaimTaskIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    try:
        claim_task(db, user, payload.task_id)
    except PassError as e:
        db.rollback()
        raise _refuse(e) from None
    db.commit()
    return user_state(db, user)
