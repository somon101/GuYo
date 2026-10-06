"""Admin Web's «ИИ-перевод» section: the DeepSeek key (never sent back in
full) and the run that fills missing Uzbek translations
(app/translation/deepseek.py)."""

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin
from app.database import get_db
from app.translation import deepseek

router = APIRouter(prefix="/admin/translation", tags=["admin-translation"])


class KeyIn(BaseModel):
    api_key: str


def _state(db: Session) -> dict:
    row = deepseek.settings_row(db)
    key = row.deepseek_api_key
    return {
        "key_set": bool(key),
        "key_masked": f"{key[:3]}…{key[-4:]}" if key else None,
        "status": row.translate_status,
        "total": row.translate_total,
        "done": row.translate_done,
        "failed": row.translate_failed,
        "error": row.translate_error,
        "missing_words": len(deepseek.missing_words(db)),
        "missing_phrases": len(deepseek.missing_phrases(db)),
    }


@router.get("")
def get_translation_state(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    return _state(db)


@router.put("/key")
def set_key(payload: KeyIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    deepseek.settings_row(db).deepseek_api_key = payload.api_key.strip() or None
    db.commit()
    return _state(db)


@router.post("/start")
def start_translation(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    if not deepseek.settings_row(db).deepseek_api_key:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Сначала сохраните ключ DeepSeek")
    if not deepseek.start(db):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Перевод уже идёт")
    return _state(db)


@router.post("/stop")
def stop_translation(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    row = deepseek.settings_row(db)
    if row.translate_status == "running":
        row.translate_status = "stopped"
        db.commit()
    return _state(db)
