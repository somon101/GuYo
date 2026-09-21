from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.achievements import CONDITION_TYPES
from app.core.deps import get_current_admin, get_current_user
from app.core.security import hash_password
from app.core.storage import delete_by_key, save_upload, url_for_key
from app.database import get_db
from app.models.achievement import Achievement, UserAchievement
from app.models.admin import Admin
from app.models.user import User
from app.schemas.achievement import UserAchievementOut
from app.schemas.user import UserCreate, UserOut, UserProfileOut

router = APIRouter(prefix="/users", tags=["users"])

# Generous enough for a real phone photo, small enough that nobody's
# profile picture eats meaningful storage -- same "don't let a user upload
# something absurd" reasoning the ZIP import size checks already use
# elsewhere in this codebase.
MAX_AVATAR_BYTES = 5 * 1024 * 1024
ALLOWED_AVATAR_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp"}


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


def _profile_out(user: User) -> UserProfileOut:
    return UserProfileOut(id=user.id, login=user.login, avatar_url=url_for_key(user.avatar_key))


@router.get("/me/profile", response_model=UserProfileOut)
def get_my_profile(user: User = Depends(get_current_user)):
    return _profile_out(user)


@router.post("/me/avatar", response_model=UserProfileOut)
def upload_my_avatar(
    avatar: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Replaces this user's avatar. Rejects anything not a real, reasonably
    sized image up front rather than silently accepting it -- the previous
    file (if any) is only deleted once the new one has actually been
    validated and saved, so a rejected upload never leaves the user with
    no photo at all."""
    if avatar.content_type not in ALLOWED_AVATAR_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Допустимые форматы: JPEG, PNG, WEBP",
        )
    data = avatar.file.read()
    if len(data) > MAX_AVATAR_BYTES:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Файл слишком большой (максимум 5 МБ)")
    if len(data) == 0:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Пустой файл")

    avatar.file.seek(0)
    new_key = save_upload(avatar, subdir=f"users/{user.id}/avatar")
    old_key = user.avatar_key
    user.avatar_key = new_key
    db.commit()
    delete_by_key(old_key)
    db.refresh(user)
    return _profile_out(user)


@router.delete("/me/avatar", response_model=UserProfileOut)
def delete_my_avatar(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Clears the avatar -- the client falls back to its generated default
    avatar the moment `avatar_url` comes back null, nothing else to do
    here."""
    old_key = user.avatar_key
    user.avatar_key = None
    db.commit()
    delete_by_key(old_key)
    return _profile_out(user)


@router.get("/me/achievements", response_model=list[UserAchievementOut])
def get_my_achievements(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Every ENABLED achievement, each with this user's own earned status
    and (for the ones not yet earned) their current progress -- computed
    fresh here, on read, so it's always accurate even if the user earned
    something through an action that hasn't explicitly re-run the granting
    check (see app/achievements/service.py) since. The backend decides all
    of this; nothing about "have I earned this" is computed in Flutter."""
    achievements = db.query(Achievement).filter(Achievement.enabled.is_(True)).order_by(Achievement.order, Achievement.id).all()
    earned_at_by_id = {
        row.achievement_id: row.earned_at
        for row in db.query(UserAchievement).filter(UserAchievement.user_id == user.id).all()
    }

    # Each condition_type's current value only needs computing once, no
    # matter how many achievements of that type exist.
    value_cache: dict[str, int] = {}

    def current_value(condition_type: str) -> int:
        if condition_type not in value_cache:
            compute = CONDITION_TYPES.get(condition_type)
            value_cache[condition_type] = compute(db, user) if compute else 0
        return value_cache[condition_type]

    return [
        UserAchievementOut(
            id=a.id,
            title=a.title,
            description=a.description,
            icon=a.icon,
            condition_type=a.condition_type,
            condition_value=a.condition_value,
            earned=a.id in earned_at_by_id,
            earned_at=earned_at_by_id.get(a.id),
            current_value=current_value(a.condition_type),
        )
        for a in achievements
    ]
