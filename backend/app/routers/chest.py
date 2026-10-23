"""The chest of the day."""

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.database import get_db
from app.models.user import User
from app.seasonpass import chest
from app.seasonpass.service import PassError

router = APIRouter(prefix="/chest", tags=["chest"])


class OpenedOut(BaseModel):
    kind: str  # "diamonds" | "freeze" (legacy "xp" records are retained)
    amount: int


class ChestOut(BaseModel):
    enabled: bool
    available: bool
    opened: OpenedOut | None = None


@router.get("", response_model=ChestOut)
def get_chest(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return chest.state(db, user)


@router.post("/open", response_model=ChestOut)
def open_today(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    try:
        chest.open_chest(db, user)
    except PassError as e:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(e)) from None
    db.commit()
    return chest.state(db, user)
