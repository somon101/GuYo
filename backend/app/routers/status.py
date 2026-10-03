"""Leaderboard statuses: the user's picker (/status) and Admin Web's
"Статусы" section (/admin/status). See app/models/status.py."""

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin, get_current_user
from app.core.storage import delete_by_key, save_upload, url_for_key
from app.database import get_db
from app.models.status import StatusEmoji, StatusPhrase
from app.models.user import User
from app.routers.admin_rating import _read_validated_icon
from app.schemas.status import (
    MyStatusIn,
    MyStatusOut,
    ReorderIn,
    StatusEmojiOption,
    StatusEmojiOut,
    StatusOptionsOut,
    StatusPhraseCreateIn,
    StatusPhraseOption,
    StatusPhraseOut,
    StatusPhraseUpdateIn,
)
from app.status import my_status

router = APIRouter(prefix="/status", tags=["status"])
admin_router = APIRouter(prefix="/admin/status", tags=["admin-status"])


def _emojis(db: Session, enabled_only: bool) -> list[StatusEmoji]:
    q = db.query(StatusEmoji)
    if enabled_only:
        q = q.filter(StatusEmoji.enabled.is_(True))
    return q.order_by(StatusEmoji.order, StatusEmoji.id).all()


def _phrases(db: Session, enabled_only: bool) -> list[StatusPhrase]:
    q = db.query(StatusPhrase)
    if enabled_only:
        q = q.filter(StatusPhrase.enabled.is_(True))
    return q.order_by(StatusPhrase.order, StatusPhrase.id).all()


# --- the user's picker ------------------------------------------------------


@router.get("/options", response_model=StatusOptionsOut)
def status_options(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return StatusOptionsOut(
        emojis=[StatusEmojiOption(id=e.id, name=e.name, image_url=url_for_key(e.image_key)) for e in _emojis(db, True)],
        phrases=[StatusPhraseOption(id=p.id, text=p.text) for p in _phrases(db, True)],
        mine=my_status(db, user),
    )


@router.put("/me", response_model=MyStatusOut)
def set_my_status(payload: MyStatusIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Sets both parts at once; null clears a part. Only an enabled item
    from the admin's lists can be picked."""
    if payload.emoji_id is not None:
        emoji = db.get(StatusEmoji, payload.emoji_id)
        if emoji is None or not emoji.enabled:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Этот эмодзи недоступен")
    if payload.phrase_id is not None:
        phrase = db.get(StatusPhrase, payload.phrase_id)
        if phrase is None or not phrase.enabled:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Эта фраза недоступна")
    user.status_emoji_id = payload.emoji_id
    user.status_phrase_id = payload.phrase_id
    db.commit()
    return my_status(db, user)


# --- Admin Web: emojis ------------------------------------------------------


def _emoji_out(e: StatusEmoji) -> StatusEmojiOut:
    return StatusEmojiOut(
        id=e.id, name=e.name, image_url=url_for_key(e.image_key), enabled=e.enabled, order=e.order, created_at=e.created_at
    )


def _emoji_or_404(db: Session, emoji_id: int) -> StatusEmoji:
    emoji = db.get(StatusEmoji, emoji_id)
    if emoji is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Emoji not found")
    return emoji


@admin_router.get("/emojis", response_model=list[StatusEmojiOut])
def list_emojis(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    return [_emoji_out(e) for e in _emojis(db, False)]


@admin_router.post("/emojis", response_model=StatusEmojiOut, status_code=status.HTTP_201_CREATED)
def create_emoji(
    name: str = Form(..., min_length=1, max_length=64),
    enabled: bool = Form(True),
    image: UploadFile = File(...),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    _read_validated_icon(image)
    last = db.query(StatusEmoji).order_by(StatusEmoji.order.desc()).first()
    emoji = StatusEmoji(
        name=name.strip(),
        enabled=enabled,
        image_key=save_upload(image, subdir="status/emojis"),
        order=(last.order + 1) if last else 0,
    )
    db.add(emoji)
    db.commit()
    db.refresh(emoji)
    return _emoji_out(emoji)


@admin_router.patch("/emojis/{emoji_id}", response_model=StatusEmojiOut)
def update_emoji(
    emoji_id: int,
    name: str | None = Form(None, min_length=1, max_length=64),
    enabled: bool | None = Form(None),
    image: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    emoji = _emoji_or_404(db, emoji_id)
    if name is not None:
        emoji.name = name.strip()
    if enabled is not None:
        emoji.enabled = enabled
    if image is not None and image.filename:
        _read_validated_icon(image)
        old = emoji.image_key
        emoji.image_key = save_upload(image, subdir="status/emojis")
        delete_by_key(old)
    db.commit()
    db.refresh(emoji)
    return _emoji_out(emoji)


@admin_router.put("/emojis/order", response_model=list[StatusEmojiOut])
def reorder_emojis(payload: ReorderIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    by_id = {e.id: e for e in db.query(StatusEmoji).filter(StatusEmoji.id.in_(payload.ids)).all()}
    missing = [i for i in payload.ids if i not in by_id]
    if missing:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Unknown emoji ids: {missing}")
    for position, emoji_id in enumerate(payload.ids):
        by_id[emoji_id].order = position
    db.commit()
    return [_emoji_out(e) for e in _emojis(db, False)]


@admin_router.delete("/emojis/{emoji_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_emoji(emoji_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Users who showed it simply lose the emoji part (the key is SET NULL)."""
    emoji = _emoji_or_404(db, emoji_id)
    key = emoji.image_key
    db.delete(emoji)
    db.commit()
    delete_by_key(key)


# --- Admin Web: phrases -----------------------------------------------------


def _phrase_out(p: StatusPhrase) -> StatusPhraseOut:
    return StatusPhraseOut(id=p.id, text=p.text, enabled=p.enabled, order=p.order, created_at=p.created_at)


def _phrase_or_404(db: Session, phrase_id: int) -> StatusPhrase:
    phrase = db.get(StatusPhrase, phrase_id)
    if phrase is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Phrase not found")
    return phrase


@admin_router.get("/phrases", response_model=list[StatusPhraseOut])
def list_phrases(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    return [_phrase_out(p) for p in _phrases(db, False)]


@admin_router.post("/phrases", response_model=StatusPhraseOut, status_code=status.HTTP_201_CREATED)
def create_phrase(payload: StatusPhraseCreateIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    last = db.query(StatusPhrase).order_by(StatusPhrase.order.desc()).first()
    phrase = StatusPhrase(text=payload.text.strip(), enabled=payload.enabled, order=(last.order + 1) if last else 0)
    db.add(phrase)
    db.commit()
    db.refresh(phrase)
    return _phrase_out(phrase)


@admin_router.patch("/phrases/{phrase_id}", response_model=StatusPhraseOut)
def update_phrase(
    phrase_id: int, payload: StatusPhraseUpdateIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    phrase = _phrase_or_404(db, phrase_id)
    if payload.text is not None:
        phrase.text = payload.text.strip()
    if payload.enabled is not None:
        phrase.enabled = payload.enabled
    db.commit()
    db.refresh(phrase)
    return _phrase_out(phrase)


@admin_router.put("/phrases/order", response_model=list[StatusPhraseOut])
def reorder_phrases(payload: ReorderIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    by_id = {p.id: p for p in db.query(StatusPhrase).filter(StatusPhrase.id.in_(payload.ids)).all()}
    missing = [i for i in payload.ids if i not in by_id]
    if missing:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Unknown phrase ids: {missing}")
    for position, phrase_id in enumerate(payload.ids):
        by_id[phrase_id].order = position
    db.commit()
    return [_phrase_out(p) for p in _phrases(db, False)]


@admin_router.delete("/phrases/{phrase_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_phrase(phrase_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    phrase = _phrase_or_404(db, phrase_id)
    db.delete(phrase)
    db.commit()
