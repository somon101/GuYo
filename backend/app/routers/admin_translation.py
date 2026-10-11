"""Admin Web's «ИИ-перевод» section: the DeepSeek key (never sent back in
full) and the run that fills missing Uzbek or English translations
(app/translation/deepseek.py)."""

from fastapi import APIRouter, Depends, HTTPException, status
from typing import Literal

from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin
from app.database import get_db
from app.translation import deepseek

router = APIRouter(prefix="/admin/translation", tags=["admin-translation"])


class KeyIn(BaseModel):
    api_key: str


class StartIn(BaseModel):
    language: Literal["uz", "en"] = "uz"


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
        "language": row.translate_language,
        # Per language, so the page can show what each run would fill.
        "missing": {
            lang: {"words": len(deepseek.missing_words(db, lang)), "phrases": len(deepseek.missing_phrases(db, lang))}
            for lang in deepseek.LANGUAGES
        },
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
def start_translation(
    payload: StartIn | None = None, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    if not deepseek.settings_row(db).deepseek_api_key:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Сначала сохраните ключ DeepSeek")
    if not deepseek.start(db, payload.language if payload else "uz"):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Перевод уже идёт")
    return _state(db)


@router.post("/stop")
def stop_translation(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    row = deepseek.settings_row(db)
    if row.translate_status == "running":
        row.translate_status = "stopped"
        db.commit()
    return _state(db)
