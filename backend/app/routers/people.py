"""Other people: their profile as everyone sees it (the «Витрина»). See app/social/profile.py."""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.database import get_db
from app.models.user import User
from app.social.profile import public_profile

router = APIRouter(prefix="/people", tags=["people"])


@router.get("/{user_id}")
def person(user_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    data = public_profile(db, user, user_id)
    if data is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
    return data
