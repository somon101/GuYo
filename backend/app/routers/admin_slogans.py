"""Admin Web's "Слоганы" section: the greeting lines shown under a user's
name on Главная.

Same shape as admin_quests.py -- list / create / patch / reorder / delete,
with an `enabled` flag so a line can be retired without losing it.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin
from app.database import get_db
from app.models.slogan import Slogan
from app.schemas.slogan import ReorderSlogansIn, SloganCreateIn, SloganOut, SloganUpdateIn

router = APIRouter(prefix="/admin/slogans", tags=["admin-slogans"])


def _out(slogan: Slogan) -> SloganOut:
    return SloganOut(
        id=slogan.id,
        text=slogan.text,
        enabled=slogan.enabled,
        order=slogan.order,
        created_at=slogan.created_at,
    )


def _get_or_404(db: Session, slogan_id: int) -> Slogan:
    slogan = db.get(Slogan, slogan_id)
    if slogan is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Slogan not found")
    return slogan


@router.get("", response_model=list[SloganOut])
def list_slogans(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Every slogan, enabled or not, in the admin's own order."""
    slogans = db.query(Slogan).order_by(Slogan.order, Slogan.id).all()
    return [_out(s) for s in slogans]


@router.post("", response_model=SloganOut, status_code=status.HTTP_201_CREATED)
def create_slogan(payload: SloganCreateIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    slogan = Slogan(text=payload.text.strip(), enabled=payload.enabled, order=payload.order)
    db.add(slogan)
    db.commit()
    db.refresh(slogan)
    return _out(slogan)


@router.patch("/{slogan_id}", response_model=SloganOut)
def update_slogan(
    slogan_id: int,
    payload: SloganUpdateIn,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Edits in place. A user who already drew this slogan today keeps
    seeing it -- with the new wording, since the pin points at the row
    rather than copying its text."""
    slogan = _get_or_404(db, slogan_id)
    if payload.text is not None:
        slogan.text = payload.text.strip()
    if payload.enabled is not None:
        slogan.enabled = payload.enabled
    if payload.order is not None:
        slogan.order = payload.order
    db.commit()
    db.refresh(slogan)
    return _out(slogan)


@router.put("/order", response_model=list[SloganOut])
def reorder_slogans(payload: ReorderSlogansIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Rewrites `order` to match the given sequence -- what the admin's
    drag-and-drop list saves."""
    slogans = db.query(Slogan).filter(Slogan.id.in_(payload.slogan_ids)).all()
    by_id = {s.id: s for s in slogans}
    missing = [i for i in payload.slogan_ids if i not in by_id]
    if missing:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Unknown slogan ids: {missing}")

    for position, slogan_id in enumerate(payload.slogan_ids):
        by_id[slogan_id].order = position
    db.commit()

    ordered = db.query(Slogan).order_by(Slogan.order, Slogan.id).all()
    return [_out(s) for s in ordered]


@router.delete("/{slogan_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_slogan(slogan_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Removes a slogan outright. Any user who had drawn it today loses
    that pin with it (the foreign key cascades) and is simply given
    another one -- nothing is left pointing at a slogan that is gone.

    Disabling is still the gentler option and is why `enabled` exists."""
    slogan = _get_or_404(db, slogan_id)
    db.delete(slogan)
    db.commit()
