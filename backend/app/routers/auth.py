from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin, get_current_user, get_current_principal, Principal
from app.core.security import create_access_token, hash_password, verify_password
from app.database import get_db
from app.models.admin import Admin
from app.models.user import User
from app.schemas.auth import LoginRequest, MeResponse, TokenResponse
import secrets

from app.core.google_auth import GoogleTokenError, verify_google_id_token
from app.schemas.user import GoogleAuthIn, GoogleAuthOut, GoogleRegisterIn, RegisterIn, login_problem

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
    # Case never matters; an exact match wins for any older pair of
    # accounts that differ only in case.
    login = payload.login.strip()
    user = db.query(User).filter(User.login == login).first() or (
        db.query(User).filter(func.lower(User.login) == login.lower()).first()
    )
    if user is None or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid login or password")
    # Аккаунт был удалён: вход в течение 30 дней возвращает его вместе со всем
    # прогрессом. После окна -- только регистрация заново.
    from app.account_deletion import restore_if_deleted

    if user.deleted_at is not None and not restore_if_deleted(db, user):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Аккаунт удалён",
        )
    token = create_access_token(subject=user.id, role="user", version=user.token_version)
    return TokenResponse(access_token=token, role="user")


class LoginAvailableOut(BaseModel):
    available: bool
    # Why not, in the user's words (rules broken, or taken).
    reason: str | None = None


@router.get("/login-available", response_model=LoginAvailableOut)
def login_available(login: str, db: Session = Depends(get_db)):
    """Live check while a login is typed at sign-up (and in Settings)."""
    from app.routers.users import login_taken

    value = login.strip().lower()
    problem = login_problem(value)
    if problem:
        return LoginAvailableOut(available=False, reason=problem)
    if login_taken(db, value):
        return LoginAvailableOut(available=False, reason="Этот логин уже занят")
    return LoginAvailableOut(available=True)


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def register_user(payload: RegisterIn, db: Session = Depends(get_db)):
    """Self-registration from the app's own sign-up wizard -- the only
    public way to create a User row (app.routers.users' create_user does
    the same thing, just admin-only). Builds the exact same row through
    new_user_row (never a second model/creation path), then logs the new
    account in immediately, same token shape login_user itself returns,
    so the client's existing _saveToken call works unchanged."""
    # Deferred import: app.routers.users itself doesn't import this
    # module, so this isn't a cycle today, but keeping User-row creation
    # importable from exactly one place (users.py) without auth.py
    # needing it at module load time is the safer default.
    from app.routers.users import new_user_row

    # A Google account is OPTIONAL at sign-up: without a token the account is
    # created with no email at all, and Google can be connected later from
    # Settings (POST /auth/google/link). Requiring one up front locked out
    # everyone who has no Google account -- the narrowest point of the funnel,
    # before a single lesson was ever played.
    identity = _google_identity(payload.id_token) if payload.id_token else None
    if identity is not None:
        if db.query(User).filter(User.google_sub == identity["sub"]).first() is not None:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Этот Google-аккаунт уже зарегистрирован")
        if db.query(User).filter(User.email == identity["email"]).first() is not None:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=_EMAIL_TAKEN)

    # Only published languages can be picked (app/languages/readiness.py).
    from app.core.content_language import reading_language as _reading
    from app.languages.readiness import KIND_LEARN, KIND_NATIVE, require_published

    require_published(db, payload.learning_language, KIND_LEARN)
    require_published(db, _reading(payload.ui_language, payload.translation_language), KIND_NATIVE)
    user = new_user_row(
        db,
        login=payload.login,
        password=payload.password,
        first_name=payload.first_name,
        last_name=payload.last_name,
        email=identity["email"] if identity is not None else None,
        google_sub=identity["sub"] if identity is not None else None,
        learning_language=payload.learning_language,
        age_group=payload.age_group,
        learning_goal=payload.learning_goal,
        referral_source=payload.referral_source,
        learning_topics=list(dict.fromkeys(payload.learning_topics or [payload.learning_goal])),
        ui_language=payload.ui_language,
        translation_language=payload.translation_language,
    )
    db.commit()
    token = create_access_token(subject=user.id, role="user", version=user.token_version)
    return TokenResponse(access_token=token, role="user")


@router.post("/google/link", status_code=status.HTTP_204_NO_CONTENT)
def link_google_account(
    payload: GoogleAuthIn,
    principal: Principal = Depends(get_current_principal),
    db: Session = Depends(get_db),
):
    """Connects a Google account to an account that already exists.

    Signing up no longer requires Google (see RegisterIn.id_token), so this is how
    the link is made afterwards -- from Settings, when the user chooses to. The
    Google account must not already belong to somebody else, and an account that
    already has one is never re-linked: silently moving the identity would break
    "sign in with Google" for whoever had it."""
    if principal.role != "user":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Доступно только пользователю")
    user = db.get(User, principal.id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
    identity = _google_identity(payload.id_token)
    if user.google_sub is not None and user.google_sub != identity["sub"]:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="К аккаунту уже привязан Google-аккаунт")
    other = db.query(User).filter(User.google_sub == identity["sub"], User.id != user.id).first()
    if other is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Этот Google-аккаунт уже привязан к другому аккаунту"
        )
    taken = db.query(User).filter(User.email == identity["email"], User.id != user.id).first()
    if taken is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=_EMAIL_TAKEN)
    user.google_sub = identity["sub"]
    user.email = identity["email"]
    db.commit()


@router.post("/logout-all", response_model=TokenResponse)
def logout_all(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Ends every session but this one: bumps the version and hands this
    device a token for the new one."""
    user.token_version = (user.token_version or 0) + 1
    db.commit()
    return TokenResponse(access_token=create_access_token(subject=user.id, role="user", version=user.token_version), role="user")


@router.get("/me", response_model=MeResponse)
def me(principal: Principal = Depends(get_current_principal), db: Session = Depends(get_db)):
    if principal.role == "admin":
        admin = db.get(Admin, principal.id)
        return MeResponse(id=admin.id, login=admin.login, role="admin")
    user = db.get(User, principal.id)
    return MeResponse(id=user.id, login=user.login, role="user")


def _google_identity(id_token: str) -> dict:
    try:
        return verify_google_id_token(id_token)
    except GoogleTokenError as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(e))


_EMAIL_TAKEN = "Аккаунт с этой почтой уже есть. Войдите по логину и паролю."


@router.post("/google", response_model=GoogleAuthOut)
def google_login(payload: GoogleAuthIn, db: Session = Depends(get_db)):
    """"Войти через Google": logs in the account made with this Google
    account, or tells the app to run the short sign-up. An email already
    used by a password account is refused -- that account logs in with its
    password (never silently linked)."""
    identity = _google_identity(payload.id_token)
    user = db.query(User).filter(User.google_sub == identity["sub"]).first()
    if user is not None:
        # Удалённый аккаунт возвращается тем же правилом, что и вход по паролю.
        from app.account_deletion import restore_if_deleted

        if user.deleted_at is not None and not restore_if_deleted(db, user):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Аккаунт удалён")
        return GoogleAuthOut(access_token=create_access_token(subject=user.id, role="user", version=user.token_version))
    if db.query(User).filter(User.email == identity["email"]).first() is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=_EMAIL_TAKEN)
    return GoogleAuthOut(
        needs_registration=True,
        email=identity["email"],
        first_name=identity["first_name"],
        last_name=identity["last_name"],
    )


@router.post("/google/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def google_register(payload: GoogleRegisterIn, db: Session = Depends(get_db)):
    """Finishes the Google sign-up through the one user-creation path
    (new_user_row). The password is random: this account signs in with
    Google."""
    from app.routers.users import new_user_row

    identity = _google_identity(payload.id_token)
    if db.query(User).filter(User.google_sub == identity["sub"]).first() is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Этот Google-аккаунт уже зарегистрирован")
    if db.query(User).filter(User.email == identity["email"]).first() is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=_EMAIL_TAKEN)
    from app.core.content_language import reading_language as _reading
    from app.languages.readiness import KIND_LEARN, KIND_NATIVE, require_published

    require_published(db, payload.learning_language, KIND_LEARN)
    require_published(db, _reading(payload.ui_language, payload.translation_language), KIND_NATIVE)
    user = new_user_row(
        db,
        login=payload.login.strip(),
        password=secrets.token_urlsafe(32),
        first_name=identity["first_name"],
        last_name=identity["last_name"],
        email=identity["email"],
        learning_language=payload.learning_language,
        age_group=payload.age_group,
        learning_goal=payload.learning_goal,
        referral_source=payload.referral_source,
        learning_topics=list(dict.fromkeys(payload.learning_topics or [payload.learning_goal])),
        ui_language=payload.ui_language,
        translation_language=payload.translation_language,
        google_sub=identity["sub"],
    )
    db.commit()
    return TokenResponse(access_token=create_access_token(subject=user.id, role="user", version=user.token_version), role="user")


class AdminPasswordIn(BaseModel):
    current_password: str
    new_password: str = Field(min_length=10, max_length=128)


@router.post("/admin/password", status_code=status.HTTP_204_NO_CONTENT)
def change_admin_password(payload: AdminPasswordIn, db: Session = Depends(get_db), admin: Admin = Depends(get_current_admin)):
    """The admin's own password change. The seed only ever creates the
    account (app/seed.py), so a changed password survives every deploy."""
    if not verify_password(payload.current_password, admin.password_hash):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Текущий пароль неверный")
    admin.password_hash = hash_password(payload.new_password)
    db.commit()
