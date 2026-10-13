"""«Проверка текста»: the app's grammar/style checker for a Russian message.

One POST, one DeepSeek call (app/text_check/deepseek.py), and the answer is
returned in the shape the app renders -- nothing is stored, nothing is
scored: this is a writing aid, not an exercise, so it touches no
WordProgress, no rating and no achievement.

The DeepSeek key is the one the AI translator already uses (Admin Web ->
«ИИ-перевод» -> LearningSettings.deepseek_api_key). No new key, nothing
hardcoded: when it isn't set, the endpoint says so plainly instead of
failing with a 500.
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.deps import get_current_user, require_current_app
from app.database import get_db
from app.models.user import User
from app.schemas.text_check import CheckRequest, CheckResultOut
from app.text_check import deepseek

log = logging.getLogger(__name__)

router = APIRouter(prefix="/text-check", tags=["text-check"])


@router.post("", response_model=CheckResultOut)
def check_text(
    payload: CheckRequest,
    db: Session = Depends(get_db),
    _user: User = Depends(get_current_user),
    _app: None = Depends(require_current_app),
):
    """Checks `payload.text` and returns the errors, the summary and the
    corrected text.

    The app is never trusted for the wording -- every message below is the
    backend's own, ready to show as-is (the Flutter client shows `detail`).
    Anything DeepSeek-related that isn't an answer is one generic sentence
    for the user, with the technical reason going to the log instead."""
    text = payload.text.strip()
    if not text:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Введите текст")

    key = deepseek.api_key(db)
    if not key:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Проверка текста пока не настроена",
        )

    try:
        return deepseek.check_text(
            key,
            text,
            payload.user_gender,
            payload.addressee_gender,
            payload.formality,
            payload.check_punctuation,
            payload.explanation_language,
        )
    except deepseek.CheckUnavailable as e:
        log.warning("text check failed: %s", e)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Сервис проверки недоступен. Попробуйте позже.",
        ) from e
