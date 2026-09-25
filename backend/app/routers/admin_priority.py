"""Admin Web's Priority configuration -- every number app/priority/
calculate.py reads, editable here and nowhere else. Mirrors
admin_word_levels.py's own CRUD shape for each of the three band tables
(a range + a contribution + admin display order), plus a single GET/PUT
pair for the one settings row.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin
from app.database import get_db
from app.models.priority import PriorityLevelBand, PriorityRecencyBand, PriorityStabilityBand
from app.priority.settings import get_priority_settings
from app.schemas.priority import (
    PriorityLevelBandCreateIn,
    PriorityLevelBandOut,
    PriorityLevelBandUpdateIn,
    PriorityRecencyBandCreateIn,
    PriorityRecencyBandOut,
    PriorityRecencyBandUpdateIn,
    PrioritySettingsIn,
    PrioritySettingsOut,
    PriorityStabilityBandCreateIn,
    PriorityStabilityBandOut,
    PriorityStabilityBandUpdateIn,
    ReorderPriorityBandsIn,
)

router = APIRouter(prefix="/admin/priority", tags=["admin-priority"])


# --- Settings ----------------------------------------------------------


@router.get("/settings", response_model=PrioritySettingsOut)
def get_settings(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    s = get_priority_settings(db)
    return PrioritySettingsOut(
        weight_level=s.weight_level,
        weight_recent_errors=s.weight_recent_errors,
        weight_recency=s.weight_recency,
        weight_stability=s.weight_stability,
        window5_weight=s.window5_weight,
        window10_weight=s.window10_weight,
        window20_weight=s.window20_weight,
        stability_window=s.stability_window,
    )


@router.put("/settings", response_model=PrioritySettingsOut)
def update_settings(payload: PrioritySettingsIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    s = get_priority_settings(db)
    s.weight_level = payload.weight_level
    s.weight_recent_errors = payload.weight_recent_errors
    s.weight_recency = payload.weight_recency
    s.weight_stability = payload.weight_stability
    s.window5_weight = payload.window5_weight
    s.window10_weight = payload.window10_weight
    s.window20_weight = payload.window20_weight
    s.stability_window = payload.stability_window
    db.commit()
    return get_settings(db)  # re-reads the row fresh, same shape as GET


# --- Давность ------------------------------------------------------------


def _recency_out(b: PriorityRecencyBand) -> PriorityRecencyBandOut:
    return PriorityRecencyBandOut(
        id=b.id, name=b.name, min_days=b.min_days, max_days=b.max_days,
        contribution=b.contribution, order=b.order, enabled=b.enabled,
    )


@router.get("/recency-bands", response_model=list[PriorityRecencyBandOut])
def list_recency_bands(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    bands = db.query(PriorityRecencyBand).order_by(PriorityRecencyBand.order, PriorityRecencyBand.id).all()
    return [_recency_out(b) for b in bands]


@router.post("/recency-bands", response_model=PriorityRecencyBandOut, status_code=status.HTTP_201_CREATED)
def create_recency_band(payload: PriorityRecencyBandCreateIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    if payload.max_days is not None and payload.max_days < payload.min_days:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Верхняя граница меньше нижней")
    band = PriorityRecencyBand(
        name=payload.name.strip(), min_days=payload.min_days, max_days=payload.max_days,
        contribution=payload.contribution, enabled=payload.enabled, order=payload.order,
    )
    db.add(band)
    db.commit()
    db.refresh(band)
    return _recency_out(band)


def _get_recency_band_or_404(db: Session, band_id: int) -> PriorityRecencyBand:
    band = db.get(PriorityRecencyBand, band_id)
    if band is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recency band not found")
    return band


@router.patch("/recency-bands/{band_id}", response_model=PriorityRecencyBandOut)
def update_recency_band(band_id: int, payload: PriorityRecencyBandUpdateIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    band = _get_recency_band_or_404(db, band_id)
    new_min = payload.min_days if payload.min_days is not None else band.min_days
    if payload.clear_max_days:
        new_max = None
    elif payload.max_days is not None:
        new_max = payload.max_days
    else:
        new_max = band.max_days
    if new_max is not None and new_max < new_min:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Верхняя граница меньше нижней")

    if payload.name is not None:
        band.name = payload.name.strip()
    band.min_days = new_min
    band.max_days = new_max
    if payload.contribution is not None:
        band.contribution = payload.contribution
    if payload.enabled is not None:
        band.enabled = payload.enabled
    if payload.order is not None:
        band.order = payload.order
    db.commit()
    db.refresh(band)
    return _recency_out(band)


@router.put("/recency-bands/order", response_model=list[PriorityRecencyBandOut])
def reorder_recency_bands(payload: ReorderPriorityBandsIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    bands = db.query(PriorityRecencyBand).filter(PriorityRecencyBand.id.in_(payload.band_ids)).all()
    by_id = {b.id: b for b in bands}
    missing = [i for i in payload.band_ids if i not in by_id]
    if missing:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Unknown band ids: {missing}")
    for position, band_id in enumerate(payload.band_ids):
        by_id[band_id].order = position
    db.commit()
    ordered = db.query(PriorityRecencyBand).order_by(PriorityRecencyBand.order, PriorityRecencyBand.id).all()
    return [_recency_out(b) for b in ordered]


@router.delete("/recency-bands/{band_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_recency_band(band_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    db.delete(_get_recency_band_or_404(db, band_id))
    db.commit()


# --- Стабильность --------------------------------------------------------


def _stability_out(b: PriorityStabilityBand) -> PriorityStabilityBandOut:
    return PriorityStabilityBandOut(
        id=b.id, name=b.name, min_percent=b.min_percent, max_percent=b.max_percent,
        contribution=b.contribution, order=b.order, enabled=b.enabled,
    )


@router.get("/stability-bands", response_model=list[PriorityStabilityBandOut])
def list_stability_bands(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    bands = db.query(PriorityStabilityBand).order_by(PriorityStabilityBand.order, PriorityStabilityBand.id).all()
    return [_stability_out(b) for b in bands]


@router.post("/stability-bands", response_model=PriorityStabilityBandOut, status_code=status.HTTP_201_CREATED)
def create_stability_band(payload: PriorityStabilityBandCreateIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    if payload.max_percent < payload.min_percent:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Верхняя граница меньше нижней")
    band = PriorityStabilityBand(
        name=payload.name.strip(), min_percent=payload.min_percent, max_percent=payload.max_percent,
        contribution=payload.contribution, enabled=payload.enabled, order=payload.order,
    )
    db.add(band)
    db.commit()
    db.refresh(band)
    return _stability_out(band)


def _get_stability_band_or_404(db: Session, band_id: int) -> PriorityStabilityBand:
    band = db.get(PriorityStabilityBand, band_id)
    if band is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Stability band not found")
    return band


@router.patch("/stability-bands/{band_id}", response_model=PriorityStabilityBandOut)
def update_stability_band(band_id: int, payload: PriorityStabilityBandUpdateIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    band = _get_stability_band_or_404(db, band_id)
    new_min = payload.min_percent if payload.min_percent is not None else band.min_percent
    new_max = payload.max_percent if payload.max_percent is not None else band.max_percent
    if new_max < new_min:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Верхняя граница меньше нижней")

    if payload.name is not None:
        band.name = payload.name.strip()
    band.min_percent = new_min
    band.max_percent = new_max
    if payload.contribution is not None:
        band.contribution = payload.contribution
    if payload.enabled is not None:
        band.enabled = payload.enabled
    if payload.order is not None:
        band.order = payload.order
    db.commit()
    db.refresh(band)
    return _stability_out(band)


@router.put("/stability-bands/order", response_model=list[PriorityStabilityBandOut])
def reorder_stability_bands(payload: ReorderPriorityBandsIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    bands = db.query(PriorityStabilityBand).filter(PriorityStabilityBand.id.in_(payload.band_ids)).all()
    by_id = {b.id: b for b in bands}
    missing = [i for i in payload.band_ids if i not in by_id]
    if missing:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Unknown band ids: {missing}")
    for position, band_id in enumerate(payload.band_ids):
        by_id[band_id].order = position
    db.commit()
    ordered = db.query(PriorityStabilityBand).order_by(PriorityStabilityBand.order, PriorityStabilityBand.id).all()
    return [_stability_out(b) for b in ordered]


@router.delete("/stability-bands/{band_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_stability_band(band_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    db.delete(_get_stability_band_or_404(db, band_id))
    db.commit()


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
