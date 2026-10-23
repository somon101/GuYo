"""Weekly friend duels."""

from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.database import get_db
from app.models.user import User
from app.seasonpass import duels
from app.seasonpass.service import PassError

router = APIRouter(prefix="/duels", tags=["duels"])


class DuelOut(BaseModel):
    id: int
    status: str
    week_start: date
    ends_at: datetime
    i_challenged: bool
    opponent_id: int
    opponent_login: str
    opponent_avatar_url: str | None = None
    my_xp: int
    their_xp: int
    won: bool | None = None


class DuelStateOut(BaseModel):
    enabled: bool
    current: DuelOut | None
    recent: list[DuelOut]


class ChallengeIn(BaseModel):
    friend_id: int


def _run(db: Session, user: User, action) -> DuelStateOut:
    try:
        action()
    except PassError as e:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(e)) from None
    db.commit()
    return duels.state(db, user)


@router.get("", response_model=DuelStateOut)
def get_state(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return duels.state(db, user)


@router.post("", response_model=DuelStateOut)
def challenge(payload: ChallengeIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _run(db, user, lambda: duels.challenge(db, user, payload.friend_id))


@router.post("/{duel_id}/accept", response_model=DuelStateOut)
def accept(duel_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _run(db, user, lambda: duels.accept(db, user, duel_id))


@router.post("/{duel_id}/decline", response_model=DuelStateOut)
def decline(duel_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _run(db, user, lambda: duels.decline(db, user, duel_id))
