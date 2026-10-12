"""Admin Web's CRUD for Achievement DEFINITIONS -- never touches
UserAchievement grants directly (see app/achievements/service.py for how
those get created). Editing an achievement's title/description/icon/color
here changes what every user who already earned it sees, but never
creates a second "medal" -- UserAchievement only ever stores a reference
to this row's own `id`.
"""

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.achievements import CONDITION_TYPE_LABELS, CONDITION_TYPES
from app.core.deps import get_current_admin
from app.core.storage import delete_by_key, save_icon_upload, url_for_key
from app.database import get_db
from app.models.achievement import VISIBILITY_HIDDEN, VISIBILITY_VISIBLE, Achievement, UserAchievement
from app.schemas.achievement import AchievementOut, ConditionTypeOut, ReorderIn

router = APIRouter(prefix="/admin/achievements", tags=["admin-achievements"])

# Same convention/limits as User.avatar_key (see app/routers/users.py) -- an
# achievement icon is just as much a real uploaded image, subject to the
# same "reject anything not a real, reasonably sized image up front" rule.
MAX_ICON_BYTES = 5 * 1024 * 1024
ALLOWED_ICON_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp"}

VALID_VISIBILITIES = {VISIBILITY_VISIBLE, VISIBILITY_HIDDEN}


def _earned_counts(db: Session) -> dict[int, int]:
    rows = db.query(UserAchievement.achievement_id, func.count()).group_by(UserAchievement.achievement_id).all()
    return dict(rows)


def _achievement_out(a: Achievement, earned_count: int | None = None) -> AchievementOut:
    if earned_count is None:
        db = Session.object_session(a)
        earned_count = (
            db.query(UserAchievement).filter(UserAchievement.achievement_id == a.id).count() if db is not None else 0
        )
    return AchievementOut(
        id=a.id,
        title=a.title,
        description=a.description,
        icon_url=url_for_key(a.icon_key),
        color=a.color,
        condition_type=a.condition_type,
        condition_value=a.condition_value,
        enabled=a.enabled,
        visibility=a.visibility,
        show_before_unlock=a.show_before_unlock,
        order=a.order,
        earned_count=earned_count,
    )


def _validate_condition_type(condition_type: str) -> None:
    if condition_type not in CONDITION_TYPES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Unknown condition_type '{condition_type}' -- must be one of {sorted(CONDITION_TYPES)}",
        )


def _validate_visibility(visibility: str) -> None:
    if visibility not in VALID_VISIBILITIES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Unknown visibility '{visibility}' -- must be one of {sorted(VALID_VISIBILITIES)}",
        )


def _read_validated_icon(icon: UploadFile) -> bytes:
    if icon.content_type not in ALLOWED_ICON_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Допустимые форматы: JPEG, PNG, WEBP",
        )
    data = icon.file.read()
    if len(data) > MAX_ICON_BYTES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Файл слишком большой (максимум 5 МБ)"
        )
    if len(data) == 0:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Пустой файл")
    icon.file.seek(0)
    return data


@router.get("", response_model=list[AchievementOut])
def list_achievements(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    achievements = db.query(Achievement).order_by(Achievement.order, Achievement.id).all()
    counts = _earned_counts(db)
    return [_achievement_out(a, counts.get(a.id, 0)) for a in achievements]


@router.get("/condition-types", response_model=list[ConditionTypeOut])
def list_condition_types(_admin=Depends(get_current_admin)):
    return [ConditionTypeOut(id=k, label=v) for k, v in CONDITION_TYPE_LABELS.items()]


@router.post("", response_model=AchievementOut, status_code=status.HTTP_201_CREATED)
def create_achievement(
    title: str = Form(..., min_length=1, max_length=255),
    description: str = Form(..., min_length=1, max_length=500),
    condition_type: str = Form(...),
    condition_value: int = Form(..., ge=1),
    color: str = Form("#6366F1"),
    visibility: str = Form(VISIBILITY_VISIBLE),
    show_before_unlock: bool = Form(True),
    enabled: bool = Form(True),
    order: int = Form(0),
    icon: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    _validate_condition_type(condition_type)
    _validate_visibility(visibility)

    icon_key = None
    if icon is not None and icon.filename:
        _read_validated_icon(icon)
        icon_key = save_icon_upload(icon, subdir="achievements/icons")

    achievement = Achievement(
        title=title.strip(),
        description=description.strip(),
        icon_key=icon_key,
        color=color,
        condition_type=condition_type,
        condition_value=condition_value,
        enabled=enabled,
        visibility=visibility,
        show_before_unlock=show_before_unlock,
        order=order,
    )
    db.add(achievement)
    db.commit()
    db.refresh(achievement)
    return _achievement_out(achievement)


def _get_achievement_or_404(db: Session, achievement_id: int) -> Achievement:
    achievement = db.get(Achievement, achievement_id)
    if achievement is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Achievement not found")
    return achievement


@router.patch("/{achievement_id}", response_model=AchievementOut)
def update_achievement(
    achievement_id: int,
    title: str | None = Form(None, min_length=1, max_length=255),
    description: str | None = Form(None, min_length=1, max_length=500),
    condition_type: str | None = Form(None),
    condition_value: int | None = Form(None, ge=1),
    color: str | None = Form(None),
    visibility: str | None = Form(None),
    show_before_unlock: bool | None = Form(None),
    enabled: bool | None = Form(None),
    order: int | None = Form(None),
    icon: UploadFile | None = File(None),
    remove_icon: bool = Form(False),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Updates this SAME row in place -- title/description/icon/color/
    threshold/visibility/enabled/order can all change freely without ever
    affecting which users already earned it (that's UserAchievement's own,
    untouched data) or duplicating the row."""
    achievement = _get_achievement_or_404(db, achievement_id)

    if title is not None:
        achievement.title = title.strip()
    if description is not None:
        achievement.description = description.strip()
    if condition_type is not None:
        _validate_condition_type(condition_type)
        achievement.condition_type = condition_type
    if condition_value is not None:
        achievement.condition_value = condition_value
    if color is not None:
        achievement.color = color
    if visibility is not None:
        _validate_visibility(visibility)
        achievement.visibility = visibility
    if show_before_unlock is not None:
        achievement.show_before_unlock = show_before_unlock
    if enabled is not None:
        achievement.enabled = enabled
    if order is not None:
        achievement.order = order

    has_new_icon = icon is not None and icon.filename
    if has_new_icon:
        _read_validated_icon(icon)
        old_key = achievement.icon_key
        achievement.icon_key = save_icon_upload(icon, subdir="achievements/icons")
        delete_by_key(old_key)
    elif remove_icon:
        delete_by_key(achievement.icon_key)
        achievement.icon_key = None

    db.commit()
    db.refresh(achievement)
    return _achievement_out(achievement)


@router.put("/order", response_model=list[AchievementOut])
def reorder_achievements(
    payload: ReorderIn,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Persists the chain's new order from Admin Web's drag-and-drop --
    `order` is set to each id's position in the given list, in one
    transaction, so a half-applied reorder can never happen."""
    achievements = db.query(Achievement).filter(Achievement.id.in_(payload.achievement_ids)).all()
    by_id = {a.id: a for a in achievements}
    missing = [i for i in payload.achievement_ids if i not in by_id]
    if missing:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Unknown achievement ids: {missing}")

    for position, achievement_id in enumerate(payload.achievement_ids):
        by_id[achievement_id].order = position
    db.commit()

    ordered = db.query(Achievement).order_by(Achievement.order, Achievement.id).all()
    return [_achievement_out(a) for a in ordered]


@router.delete("/{achievement_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_achievement(achievement_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Deletes the achievement for everyone: users who earned it lose it
    too (their grants go with it, ondelete=CASCADE). Admin Web says how
    many that is before asking. To retire one but let its holders keep it,
    archive it instead (`enabled: false`, see GET /users/me/achievements)."""
    achievement = _get_achievement_or_404(db, achievement_id)
    icon_key = achievement.icon_key
    db.delete(achievement)
    db.commit()
    delete_by_key(icon_key)
