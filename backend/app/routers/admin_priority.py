"""Admin Web's Priority configuration: the settings row (memory model
cut-offs, auto-quests, auto-lessons) and the named level bands.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin
from app.database import get_db
from app.models.priority import PriorityLevelBand
from app.priority.settings import get_priority_settings
from app.schemas.priority import (
    PriorityLevelBandCreateIn,
    PriorityLevelBandOut,
    PriorityLevelBandUpdateIn,
    PrioritySettingsIn,
    PrioritySettingsOut,
    ReorderPriorityBandsIn,
)

router = APIRouter(prefix="/admin/priority", tags=["admin-priority"])


# --- Settings ----------------------------------------------------------


@router.get("/settings", response_model=PrioritySettingsOut)
def get_settings(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    s = get_priority_settings(db)
    return PrioritySettingsOut(
        personal_quest_min_attempts=s.personal_quest_min_attempts,
        personal_quest_weak_error_rate=s.personal_quest_weak_error_rate,
        personal_quest_min_words=s.personal_quest_min_words,
        personal_quest_max_words=s.personal_quest_max_words,
        personal_quest_reward_points=s.personal_quest_reward_points,
        adaptive_lesson_min_words=s.adaptive_lesson_min_words,
        memory_target_retention=s.memory_target_retention,
        memory_critical_below=s.memory_critical_below,
        memory_high_below=s.memory_high_below,
        memory_minimal_above=s.memory_minimal_above,
    )


@router.put("/settings", response_model=PrioritySettingsOut)
def update_settings(payload: PrioritySettingsIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    s = get_priority_settings(db)
    s.personal_quest_min_attempts = payload.personal_quest_min_attempts
    s.personal_quest_weak_error_rate = payload.personal_quest_weak_error_rate
    s.personal_quest_min_words = payload.personal_quest_min_words
    s.personal_quest_max_words = payload.personal_quest_max_words
    s.personal_quest_reward_points = payload.personal_quest_reward_points
    s.adaptive_lesson_min_words = payload.adaptive_lesson_min_words
    s.memory_target_retention = payload.memory_target_retention
    s.memory_critical_below = payload.memory_critical_below
    s.memory_high_below = payload.memory_high_below
    s.memory_minimal_above = payload.memory_minimal_above
    db.commit()
    return get_settings(db)  # re-reads the row fresh, same shape as GET


# --- Priority Level --------------------------------------------------------


def _level_band_out(b: PriorityLevelBand) -> PriorityLevelBandOut:
    return PriorityLevelBandOut(
        id=b.id, name=b.name, min_score=b.min_score, max_score=b.max_score, order=b.order, enabled=b.enabled,
    )


@router.get("/level-bands", response_model=list[PriorityLevelBandOut])
def list_level_bands(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    bands = db.query(PriorityLevelBand).order_by(PriorityLevelBand.order, PriorityLevelBand.id).all()
    return [_level_band_out(b) for b in bands]


@router.post("/level-bands", response_model=PriorityLevelBandOut, status_code=status.HTTP_201_CREATED)
def create_level_band(payload: PriorityLevelBandCreateIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    if payload.max_score is not None and payload.max_score < payload.min_score:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Верхняя граница меньше нижней")
    band = PriorityLevelBand(
        name=payload.name.strip(), min_score=payload.min_score, max_score=payload.max_score,
        enabled=payload.enabled, order=payload.order,
    )
    db.add(band)
    db.commit()
    db.refresh(band)
    return _level_band_out(band)


def _get_level_band_or_404(db: Session, band_id: int) -> PriorityLevelBand:
    band = db.get(PriorityLevelBand, band_id)
    if band is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Priority level band not found")
    return band


@router.patch("/level-bands/{band_id}", response_model=PriorityLevelBandOut)
def update_level_band(band_id: int, payload: PriorityLevelBandUpdateIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    band = _get_level_band_or_404(db, band_id)
    new_min = payload.min_score if payload.min_score is not None else band.min_score
    if payload.clear_max_score:
        new_max = None
    elif payload.max_score is not None:
        new_max = payload.max_score
    else:
        new_max = band.max_score
    if new_max is not None and new_max < new_min:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Верхняя граница меньше нижней")

    if payload.name is not None:
        band.name = payload.name.strip()
    band.min_score = new_min
    band.max_score = new_max
    if payload.enabled is not None:
        band.enabled = payload.enabled
    if payload.order is not None:
        band.order = payload.order
    db.commit()
    db.refresh(band)
    return _level_band_out(band)


@router.put("/level-bands/order", response_model=list[PriorityLevelBandOut])
def reorder_level_bands(payload: ReorderPriorityBandsIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    bands = db.query(PriorityLevelBand).filter(PriorityLevelBand.id.in_(payload.band_ids)).all()
    by_id = {b.id: b for b in bands}
    missing = [i for i in payload.band_ids if i not in by_id]
    if missing:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Unknown band ids: {missing}")
    for position, band_id in enumerate(payload.band_ids):
        by_id[band_id].order = position
    db.commit()
    ordered = db.query(PriorityLevelBand).order_by(PriorityLevelBand.order, PriorityLevelBand.id).all()
    return [_level_band_out(b) for b in ordered]


@router.delete("/level-bands/{band_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_level_band(band_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    db.delete(_get_level_band_or_404(db, band_id))
    db.commit()
