from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.achievements import CONDITION_TYPES, lessons_completed_count, streak_days_count, words_learned_count
from app.core.deps import get_current_admin, get_current_user
from app.core.security import hash_password
from app.core.storage import delete_by_key, save_bytes, url_for_key
from app.database import get_db
from app.models.achievement import VISIBILITY_HIDDEN, Achievement, UserAchievement
from app.models.admin import Admin
from app.models.rating import SeasonHistory
from app.models.user import User
from app.rating import (
    current_rank_for_points,
    get_active_season,
    get_or_create_user_rating,
    get_rating_settings,
    next_rank_for_points,
    rank_position_for_user,
    sync_season_states,
)
from app.schemas.achievement import UserAchievementOut
from app.schemas.rating import SeasonHistoryOut, SeasonOut, UserRatingOut, rank_public_out
from app.schemas.user import UserCreate, UserOut, UserProfileOut

router = APIRouter(prefix="/users", tags=["users"])

# Generous enough for a real phone photo, small enough that nobody's
# profile picture eats meaningful storage -- same "don't let a user upload
# something absurd" reasoning the ZIP import size checks already use
# elsewhere in this codebase.
MAX_AVATAR_BYTES = 5 * 1024 * 1024
ALLOWED_AVATAR_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp"}
# Keyed by the SAME validated content_type above -- the extension a stored
# avatar file gets on disk must come from here, never from the client's own
# filename. A real Android gallery pick can hand back a content:// name
# with no extension at all (or the wrong one); storing under that name
# leaves StaticFiles unable to guess a Content-Type on the way back out,
# so it serves text/plain for a real photo and the client's Image.network
# silently fails to render it -- exactly the bug this fixes.
_AVATAR_EXTENSION_BY_CONTENT_TYPE = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
}


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


@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_user(user_id: int, db: Session = Depends(get_db), _admin: Admin = Depends(get_current_admin)):
    """Permanently removes a user and everything scoped to them -- every
    other table's own user_id column is declared ondelete="CASCADE"
    (UserRating, WordProgress, Lesson/LessonWord/LessonExercise,
    UserAchievement, SeasonHistory, UserQuestWordDay, LearningSession, ...),
    so this one delete is enough; nothing here re-implements that cleanup
    by hand. Mainly for removing test/bot accounts (e.g. ones seeded to
    exercise the rating ladder) without leaving orphaned rows anywhere --
    a REAL user's own account is never deleted through any UI path today,
    only this direct admin call."""
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    avatar_key = user.avatar_key
    db.delete(user)
    db.commit()
    delete_by_key(avatar_key)


def _profile_out(db: Session, user: User) -> UserProfileOut:
    return UserProfileOut(
        id=user.id,
        login=user.login,
        avatar_url=url_for_key(user.avatar_key),
        current_streak_days=streak_days_count(db, user),
        lessons_completed=lessons_completed_count(db, user),
        words_learned=words_learned_count(db, user),
    )


@router.get("/me/profile", response_model=UserProfileOut)
def get_my_profile(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _profile_out(db, user)


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

    extension = _AVATAR_EXTENSION_BY_CONTENT_TYPE[avatar.content_type]
    new_key = save_bytes(data, subdir=f"users/{user.id}/avatar", filename_hint=f"avatar{extension}")
    old_key = user.avatar_key
    user.avatar_key = new_key
    db.commit()
    delete_by_key(old_key)
    db.refresh(user)
    return _profile_out(db, user)


@router.delete("/me/avatar", response_model=UserProfileOut)
def delete_my_avatar(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Clears the avatar -- the client falls back to its generated default
    avatar the moment `avatar_url` comes back null, nothing else to do
    here."""
    old_key = user.avatar_key
    user.avatar_key = None
    db.commit()
    delete_by_key(old_key)
    return _profile_out(db, user)


@router.get("/me/achievements", response_model=list[UserAchievementOut])
def get_my_achievements(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Every ENABLED achievement, each with this user's own earned status
    and (for the ones not yet earned) their current progress -- computed
    fresh here, on read, so it's always accurate even if the user earned
    something through an action that hasn't explicitly re-run the granting
    check (see app/achievements/service.py) since. The backend decides all
    of this; nothing about "have I earned this" is computed in Flutter."""
    achievements = (
        db.query(Achievement).filter(Achievement.enabled.is_(True)).order_by(Achievement.order, Achievement.id).all()
    )
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

    result = []
    for a in achievements:
        earned = a.id in earned_at_by_id
        is_hidden = a.visibility == VISIBILITY_HIDDEN

        if not earned and is_hidden and not a.show_before_unlock:
            # Fully invisible until earned -- omitted entirely, not just
            # styled as locked, so it can't be discovered early.
            continue

        if not earned and is_hidden:
            # Visible as a locked mystery tile: the real icon (the client
            # dims it), but the condition itself stays withheld.
            result.append(
                UserAchievementOut(
                    id=a.id,
                    title=None,
                    description=None,
                    icon_url=url_for_key(a.icon_key),
                    color=a.color,
                    condition_type=None,
                    condition_value=None,
                    current_value=None,
                    earned=False,
                    earned_at=None,
                )
            )
            continue

        result.append(
            UserAchievementOut(
                id=a.id,
                title=a.title,
                description=a.description,
                icon_url=url_for_key(a.icon_key),
                color=a.color,
                condition_type=a.condition_type,
                condition_value=a.condition_value,
                current_value=current_value(a.condition_type),
                earned=earned,
                earned_at=earned_at_by_id.get(a.id),
            )
        )
    return result


@router.get("/me/rating", response_model=UserRatingOut)
def get_my_rating(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Everything the Profile screen's "Рейтинг" block needs in one round
    trip -- current points, current season, current rank (+ the next rank
    up, for a progress bar), and past seasons' frozen results. A fully
    separate system from achievements (see app/rating/): nothing here
    touches Achievement/UserAchievement, and this never recomputes a past
    season's SeasonHistory row from the CURRENT rating -- that snapshot is
    permanent the moment a season ends."""
    # Brings the season schedule up to date first, so "which season is
    # running" is answered from the stored periods rather than from
    # whenever the background sweep last ran (see app/rating/scheduler.py).
    sync_season_states(db)

    rating = get_or_create_user_rating(db, user.id)
    rank = current_rank_for_points(db, rating.total_points)
    next_rank = next_rank_for_points(db, rating.total_points)
    season = get_active_season(db)

    history_rows = (
        db.query(SeasonHistory)
        .filter(SeasonHistory.user_id == user.id)
        .order_by(SeasonHistory.ended_at.desc())
        .all()
    )
    history = [
        SeasonHistoryOut(
            season_id=row.season_id,
            season_name=row.season.name if row.season else "",
            points=row.points,
            rank=rank_public_out(row.rank) if row.rank_id else None,
            ended_at=row.ended_at,
        )
        for row in history_rows
    ]

    return UserRatingOut(
        total_points=rating.total_points,
        season=SeasonOut.model_validate(season, from_attributes=True) if season else None,
        rank=rank_public_out(rank),
        next_rank=rank_public_out(next_rank),
        points_to_next_rank=(next_rank.min_points - rating.total_points) if next_rank else None,
        history=history,
        points_per_learned_word=get_rating_settings(db).points_per_learned_word,
        rank_position=rank_position_for_user(db, rank, rating) if rank else None,
    )
