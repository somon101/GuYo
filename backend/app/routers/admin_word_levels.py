"""Admin Web's word-level ladder CRUD: names and memory days per level.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin
from app.database import get_db
from app.models.quest import Quest
from app.models.word_level import WordLevel
from app.schemas.word_level import (
    ReorderWordLevelsIn,
    WordLevelCreateIn,
    WordLevelOut,
    WordLevelUpdateIn,
)

router = APIRouter(prefix="/admin/word-levels", tags=["admin-word-levels"])


def _assert_days_free(db: Session, min_days: float, enabled: bool, exclude_id: int | None = None) -> None:
    """Two enabled levels cannot start at the same number of memory days."""
    if not enabled:
        return
    query = db.query(WordLevel).filter(WordLevel.enabled.is_(True), WordLevel.min_days == min_days)
    if exclude_id is not None:
        query = query.filter(WordLevel.id != exclude_id)
    clash = query.first()
    if clash is not None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Уровень «{clash.name}» уже начинается с {min_days:g} дн.",
        )


def _out(level: WordLevel) -> WordLevelOut:
    return WordLevelOut(id=level.id, name=level.name, min_days=level.min_days, order=level.order, enabled=level.enabled)


@router.get("", response_model=list[WordLevelOut])
def list_word_levels(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    levels = db.query(WordLevel).order_by(WordLevel.order, WordLevel.id).all()
    return [_out(w) for w in levels]


@router.post("", response_model=WordLevelOut, status_code=status.HTTP_201_CREATED)
def create_word_level(payload: WordLevelCreateIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    _assert_days_free(db, payload.min_days, payload.enabled)

    level = WordLevel(
        name=payload.name.strip(), min_days=payload.min_days, enabled=payload.enabled, order=payload.order,
    )
    db.add(level)
    db.commit()
    db.refresh(level)
    return _out(level)


def _get_level_or_404(db: Session, level_id: int) -> WordLevel:
    level = db.get(WordLevel, level_id)
    if level is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Word level not found")
    return level


@router.patch("/{level_id}", response_model=WordLevelOut)
def update_word_level(
    level_id: int, payload: WordLevelUpdateIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    level = _get_level_or_404(db, level_id)

    new_enabled = payload.enabled if payload.enabled is not None else level.enabled

    _assert_days_free(
        db, payload.min_days if payload.min_days is not None else level.min_days, new_enabled, exclude_id=level.id
    )

    if payload.name is not None:
        level.name = payload.name.strip()
    level.enabled = new_enabled
    if payload.order is not None:
        level.order = payload.order
    if payload.min_days is not None:
        level.min_days = payload.min_days

    db.commit()
    db.refresh(level)
    return _out(level)


@router.put("/order", response_model=list[WordLevelOut])
def reorder_word_levels(payload: ReorderWordLevelsIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    levels = db.query(WordLevel).filter(WordLevel.id.in_(payload.word_level_ids)).all()
    by_id = {w.id: w for w in levels}
    missing = [i for i in payload.word_level_ids if i not in by_id]
    if missing:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Unknown word level ids: {missing}")

    for position, level_id in enumerate(payload.word_level_ids):
        by_id[level_id].order = position
    db.commit()

    ordered = db.query(WordLevel).order_by(WordLevel.order, WordLevel.id).all()
    return [_out(w) for w in ordered]


@router.delete("/{level_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_word_level(level_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Refuses to delete a level any Quest still targets -- disable it
    instead. Deleting a level in active use would leave that Quest
    pointing at nothing."""
    level = _get_level_or_404(db, level_id)
    referenced = db.query(Quest).filter(Quest.word_level_id == level_id).first() is not None
    if referenced:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Этот уровень используется в квесте -- отключите его вместо удаления",
        )
    db.delete(level)
    db.commit()
