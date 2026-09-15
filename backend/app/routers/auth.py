from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.deps import get_current_principal, Principal
from app.core.security import create_access_token, verify_password
from app.database import get_db
from app.models.admin import Admin
from app.models.user import User
from app.schemas.auth import LoginRequest, MeResponse, TokenResponse

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/admin/login", response_model=TokenResponse)
def admin_login(payload: LoginRequest, db: Session = Depends(get_db)):
    admin = db.query(Admin).filter(Admin.login == payload.login).first()
    if admin is None or not verify_password(payload.password, admin.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid login or password")
    token = create_access_token(subject=admin.id, role="admin")
    return TokenResponse(access_token=token, role="admin")


@router.post("/login", response_model=TokenResponse)
def user_login(payload: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.login == payload.login).first()
    if user is None or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid login or password")
    token = create_access_token(subject=user.id, role="user")
    return TokenResponse(access_token=token, role="user")


@router.get("/me", response_model=MeResponse)
def me(principal: Principal = Depends(get_current_principal), db: Session = Depends(get_db)):
    if principal.role == "admin":
        admin = db.get(Admin, principal.id)
        return MeResponse(id=admin.id, login=admin.login, role="admin")
    user = db.get(User, principal.id)
    return MeResponse(id=user.id, login=user.login, role="user")
