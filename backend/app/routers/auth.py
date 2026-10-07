from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.deps import get_current_principal, Principal
from app.core.security import create_access_token, verify_password
from app.database import get_db
from app.models.admin import Admin
from app.models.user import User
from app.schemas.auth import LoginRequest, MeResponse, TokenResponse
import secrets

from app.core.google_auth import GoogleTokenError, verify_google_id_token
from app.schemas.user import GoogleAuthIn, GoogleAuthOut, GoogleRegisterIn, RegisterIn

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

    # The email is the linked Google account's, never typed by the user.
    identity = _google_identity(payload.id_token)
    if db.query(User).filter(User.google_sub == identity["sub"]).first() is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Этот Google-аккаунт уже зарегистрирован")
    if db.query(User).filter(User.email == identity["email"]).first() is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=_EMAIL_TAKEN)

    user = new_user_row(
        db,
        login=payload.login,
        password=payload.password,
        first_name=payload.first_name,
        last_name=payload.last_name,
        email=identity["email"],
        google_sub=identity["sub"],
        learning_language=payload.learning_language,
        age_group=payload.age_group,
        learning_goal=payload.learning_goal,
        referral_source=payload.referral_source,
        learning_topics=list(dict.fromkeys(payload.learning_topics or [payload.learning_goal])),
        ui_language=payload.ui_language,
        translation_language=payload.translation_language,
    )
    db.commit()
    token = create_access_token(subject=user.id, role="user")
    return TokenResponse(access_token=token, role="user")


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
        return GoogleAuthOut(access_token=create_access_token(subject=user.id, role="user"))
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
    return TokenResponse(access_token=create_access_token(subject=user.id, role="user"), role="user")
