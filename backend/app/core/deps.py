"""FastAPI auth dependencies. Frontend is never trusted for authorization --
every admin-only or user-only route depends on one of these to check the
JWT's role claim server-side."""
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.security import TokenPayload, decode_access_token
from app.database import get_db
from app.models.admin import Admin
from app.models.user import User

bearer_scheme = HTTPBearer(auto_error=False)


def _get_token_payload(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> TokenPayload:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )
    payload = decode_access_token(credentials.credentials)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return payload


def get_current_admin(
    payload: TokenPayload = Depends(_get_token_payload),
    db: Session = Depends(get_db),
) -> Admin:
    if payload.role != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required")
    admin = db.get(Admin, payload.subject)
    if admin is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Admin not found")
    return admin


def get_current_user(
    payload: TokenPayload = Depends(_get_token_payload),
    db: Session = Depends(get_db),
) -> User:
    if payload.role != "user":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="User access required")
    user = db.get(User, payload.subject)
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    return user


class Principal:
    """Either an admin or a regular user -- used for read routes both can call."""

    def __init__(self, role: str, id: int):
        self.role = role
        self.id = id


def get_current_principal(
    payload: TokenPayload = Depends(_get_token_payload),
    db: Session = Depends(get_db),
) -> Principal:
    if payload.role == "admin":
        if db.get(Admin, payload.subject) is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Admin not found")
    elif payload.role == "user":
        if db.get(User, payload.subject) is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    else:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid role")
    return Principal(role=payload.role, id=payload.subject)
