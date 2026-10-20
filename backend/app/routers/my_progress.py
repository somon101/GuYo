"""«Мой путь»: the person's learning over the last weeks."""

from datetime import date

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.database import get_db
from app.models.user import User
from app.progress.stats import total_active_days, total_learned, weekly_series

router = APIRouter(prefix="/users/me", tags=["progress"])


class WeekOut(BaseModel):
    week_start: date
    words: int
    active_days: int


class ProgressOut(BaseModel):
    total_words: int
    total_active_days: int
    weeks: list[WeekOut]


@router.get("/progress", response_model=ProgressOut)
def my_progress(weeks: int = Query(12, ge=4, le=52), db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return ProgressOut(
        total_words=total_learned(db, user.id),
        total_active_days=total_active_days(db, user.id),
        weeks=weekly_series(db, user.id, weeks),
    )
