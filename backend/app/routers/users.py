from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin
from app.core.security import hash_password
from app.database import get_db
from app.models.admin import Admin
from app.models.user import User
from app.schemas.user import UserCreate, UserOut

router = APIRouter(prefix="/users", tags=["users"])


@router.get("", response_model=list[UserOut])
def list_users(db: Session = Depends(get_db), _admin: Admin = Depends(get_current_admin)):
    return db.query(User).order_by(User.id).all()


@router.post("", response_model=UserOut, status_code=status.HTTP_201_CREATED)
def create_user(payload: UserCreate, db: Session = Depends(get_db), _admin: Admin = Depends(get_current_admin)):
    exists = db.query(User).filter(User.login == payload.login).first()
    if exists is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Login already taken")

    user = User(login=payload.login, password_hash=hash_password(payload.password))
    db.add(user)
    db.commit()
    db.refresh(user)
    return user
