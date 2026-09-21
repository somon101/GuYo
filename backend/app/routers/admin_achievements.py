"""Admin Web's CRUD for Achievement DEFINITIONS -- never touches
UserAchievement grants directly (see app/achievements/service.py for how
those get created). Editing an achievement's title/description/icon here
changes what every user who already earned it sees, but never creates a
second "medal" -- UserAchievement only ever stores a reference to this
row's own `id`.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.achievements import ACHIEVEMENT_ICONS, CONDITION_TYPE_LABELS
from app.core.deps import get_current_admin
from app.database import get_db
from app.models.achievement import Achievement, UserAchievement
from app.schemas.achievement import (
    AchievementIconOut,
    AchievementIn,
    AchievementOut,
    ConditionTypeOut,
)

router = APIRouter(prefix="/admin/achievements", tags=["admin-achievements"])


@router.get("", response_model=list[AchievementOut])
def list_achievements(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    return db.query(Achievement).order_by(Achievement.order, Achievement.id).all()


@router.get("/icons", response_model=list[AchievementIconOut])
def list_achievement_icons(_admin=Depends(get_current_admin)):
    return [AchievementIconOut(id=k, emoji=v) for k, v in ACHIEVEMENT_ICONS.items()]


@router.get("/condition-types", response_model=list[ConditionTypeOut])
def list_condition_types(_admin=Depends(get_current_admin)):
    return [ConditionTypeOut(id=k, label=v) for k, v in CONDITION_TYPE_LABELS.items()]


@router.post("", response_model=AchievementOut, status_code=status.HTTP_201_CREATED)
def create_achievement(payload: AchievementIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    achievement = Achievement(**payload.model_dump())
    db.add(achievement)
    db.commit()
    db.refresh(achievement)
    return achievement


def _get_achievement_or_404(db: Session, achievement_id: int) -> Achievement:
    achievement = db.get(Achievement, achievement_id)
    if achievement is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Achievement not found")
    return achievement


@router.patch("/{achievement_id}", response_model=AchievementOut)
def update_achievement(
    achievement_id: int,
    payload: AchievementIn,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Updates this SAME row in place -- title/description/icon/threshold/
    enabled/order can all change freely without ever affecting which users
    already earned it (that's UserAchievement's own, untouched data)."""
    achievement = _get_achievement_or_404(db, achievement_id)
    for field, value in payload.model_dump().items():
        setattr(achievement, field, value)
    db.commit()
    db.refresh(achievement)
    return achievement


@router.delete("/{achievement_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_achievement(achievement_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Refuses to delete an achievement any user has already earned --
    disable it instead (`enabled: false`) if it shouldn't be earnable
    anymore. This is deliberate: a user's earned badge is a historical
    fact, and silently erasing it (or the CASCADE-deleted grant that would
    otherwise leave no record of it) just because an admin deleted the
    definition would contradict "already earned achievement should keep
    being shown"."""
    achievement = _get_achievement_or_404(db, achievement_id)
    has_grants = db.query(UserAchievement).filter(UserAchievement.achievement_id == achievement_id).first() is not None
    if has_grants:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Это достижение уже получено пользователями -- отключите его вместо удаления",
        )
    db.delete(achievement)
    db.commit()
