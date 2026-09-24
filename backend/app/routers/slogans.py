"""The greeting slogan a user sees today."""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.database import get_db
from app.models.user import User
from app.schemas.slogan import TodaySloganOut
from app.slogans import slogan_for_today

router = APIRouter(tags=["slogans"])


@router.get("/slogans/today", response_model=TodaySloganOut)
def get_todays_slogan(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """This user's slogan for today -- drawn at random the first time it is
    asked for on a given day, then held for the rest of that day (see
    app/slogans/service.py). Null when an admin has no enabled slogans, in
    which case the app shows its own built-in line."""
    slogan = slogan_for_today(db, user)
    db.commit()
    return TodaySloganOut(text=slogan.text if slogan else None)
