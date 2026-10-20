"""FastAPI auth dependencies. Frontend is never trusted for authorization --
every admin-only or user-only route depends on one of these to check the
JWT's role claim server-side."""
from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.config import get_settings
from app.core.security import TokenPayload, decode_access_token
from app.database import get_db
from app.models.admin import Admin
from app.models.user import User
from app.core.content_language import UI_LANGUAGES, set_content_language_for

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


def _reading_ui_language(user: User, header: str | None) -> str | None:
    """The app sends the interface language it shows (X-UI-Language), so a
    language switch is applied at once -- before the profile save lands --
    and content arrives in the language on screen. Older apps send none."""
    return header if header in UI_LANGUAGES else user.ui_language


def get_current_user(
    payload: TokenPayload = Depends(_get_token_payload),
    db: Session = Depends(get_db),
    x_ui_language: str | None = Header(default=None),
) -> User:
    if payload.role != "user":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="User access required")
    user = db.get(User, payload.subject)
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    if payload.version != (user.token_version or 0):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Сессия завершена")
    # Аккаунт помечен удалённым: старый токен больше не пускает. Войти заново
    # по логину и паролю можно -- это и есть восстановление (30 дней).
    if user.deleted_at is not None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Аккаунт удалён"
        )
    set_content_language_for(
        _reading_ui_language(user, x_ui_language), user.translation_language, user.learning_language
    )
    return user


class Principal:
    """Either an admin or a regular user -- used for read routes both can call."""

    def __init__(self, role: str, id: int):
        self.role = role
        self.id = id


def get_current_principal(
    payload: TokenPayload = Depends(_get_token_payload),
    db: Session = Depends(get_db),
    x_ui_language: str | None = Header(default=None),
) -> Principal:
    if payload.role == "admin":
        if db.get(Admin, payload.subject) is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Admin not found")
    elif payload.role == "user":
        user = db.get(User, payload.subject)
        if user is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
        if payload.version != (user.token_version or 0):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Сессия завершена")
        if user.deleted_at is not None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Аккаунт удалён")
        set_content_language_for(
            _reading_ui_language(user, x_ui_language), user.translation_language, user.learning_language
        )
    else:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid role")
    return Principal(role=payload.role, id=payload.subject)


def require_current_app(x_app_build: int | None = Header(default=None)) -> None:
    """Rejects apps older than MIN_APP_BUILD with 426 "update the app".
    Apps that predate the header send none and count as build 0."""
    minimum = get_settings().min_app_build
    if minimum and (x_app_build or 0) < minimum:
        raise HTTPException(status_code=426, detail="Обновите приложение")
