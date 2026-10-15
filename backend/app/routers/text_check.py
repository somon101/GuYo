"""«Проверка текста»: the app's grammar/style checker for a Russian message.

One GET to learn the limits, one POST per message. The POST is the only place
that talks to DeepSeek, and everything that decides whether a check may happen
at all -- the admin's switches, the daily allowance, the answer cache and the
run journal -- lives in app/text_check/service.py, so this router stays a thin
wrapper that turns those decisions into HTTP.

Nothing here is stored per user beyond the run journal (who checked how much
today, for the limit and the statistics): the messages themselves are only
ever kept in the shared answer cache, which exists to make a repeated text
instant and free. No score, streak or achievement is touched -- this is a
writing aid, not an exercise.

The DeepSeek key is the one the AI translator already uses (Admin Web ->
«ИИ-перевод» -> LearningSettings.deepseek_api_key). No new key, nothing
hardcoded: when it isn't set, the endpoint says so plainly instead of failing
with a 500.
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.deps import get_current_user, require_current_app
from app.database import get_db
from app.models.user import User
from app.schemas.text_check import CheckInfoOut, CheckRequest, CheckResultOut
from app.text_check import deepseek, service

log = logging.getLogger(__name__)

router = APIRouter(prefix="/text-check", tags=["text-check"])


def _info(db: Session, user: User) -> CheckInfoOut:
    from app.models.notification import ReminderSettings

    settings = service.get_settings(db)
    quota = service.text_check_quota(db, user)
    # How the screen's own confirmations are shown is an admin choice made in
    # Admin Web -> Уведомления; it rides along with the checker's own settings
    # so the app needs no second request to learn it.
    reminders = db.query(ReminderSettings).first()
    return CheckInfoOut(
        enabled=settings.enabled,
        max_chars=settings.max_chars,
        remaining=quota.remaining,
        daily_limit=quota.daily_limit,
        unlimited=quota.unlimited,
        confirmation_style=reminders.confirmation_style if reminders else "banner",
    )


@router.get("/info", response_model=CheckInfoOut)
def check_info(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    _app: None = Depends(require_current_app),
):
    """What the screen shows before the first message: is the checker on, how
    long may a message be, and how many checks are left today."""
    return _info(db, user)


@router.post("", response_model=CheckResultOut)
def check_text(
    payload: CheckRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    _app: None = Depends(require_current_app),
):
    """Checks `payload.text` and returns the errors, the summary and the
    corrected text.

    The app is never trusted for the wording -- every message below is the
    backend's own, ready to show as-is (the Flutter client shows `detail`).
    Anything DeepSeek-related that isn't an answer is one generic sentence for
    the user, with the technical reason going to the log instead."""
    settings = service.get_settings(db)
    if not settings.enabled:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Проверка текста сейчас недоступна")

    text = payload.text.strip()
    if not text:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Введите текст")
    if len(text) > settings.max_chars:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Слишком длинный текст: максимум {settings.max_chars} символов",
        )

    try:
        quota = service.check_quota(db, user)
    except service.TextCheckLimitReached as e:
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=str(e)) from e

    params = {
        "user_gender": payload.user_gender,
        "addressee_gender": payload.addressee_gender,
        "formality": payload.formality,
        "check_punctuation": payload.check_punctuation,
        "explanation_language": payload.explanation_language,
    }
    key = service.fingerprint(text, params)

    # An exact match under these very settings: hand back what we already know.
    # `quota` still stands as it was read -- a cached check costs nothing, so
    # it is not charged, and the counter the app shows must not move.
    entry = service.cache_lookup(db, key)
    if entry is not None:
        result = service.cache_hit(db, entry)
        # The check is kept in full (see app/models/text_check.py): the text as
        # written, the settings it ran with and the answer the user was shown. The
        # prompt is the one stored with the first check of this text -- nothing was
        # asked of the model this time.
        service.record_run(
            db,
            user,
            chars=len(text),
            cached=True,
            succeeded=True,
            text=text,
            params=params,
            answer=str(result),
        )
        db.commit()
        return {
            **result,
            "cached": True,
            "remaining": quota.remaining,
            "daily_limit": quota.daily_limit,
            "unlimited": quota.unlimited,
        }

    api_key = service.api_key(db)
    if not api_key:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Проверка текста пока не настроена")

    try:
        result = deepseek.check_text(
            api_key,
            text,
            payload.user_gender,
            payload.addressee_gender,
            payload.formality,
            payload.check_punctuation,
            payload.explanation_language,
        )
    except deepseek.CheckUnavailable as e:
        # Journalled for the statistics, but a failure is never charged: the
        # user got nothing, so they pay nothing. The text is kept -- what people
        # ask about is worth seeing even when the model was down.
        service.record_run(
            db,
            user,
            chars=len(text),
            cached=False,
            succeeded=False,
            text=text,
            params=params,
            prompt=deepseek._prompt(
                text,
                payload.user_gender,
                payload.addressee_gender,
                payload.formality,
                payload.check_punctuation,
                payload.explanation_language,
            ),
            model=deepseek.MODEL,
        )
        db.commit()
        log.warning("text check failed: %s", e)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Сервис проверки недоступен. Попробуйте позже.",
        ) from e

    service.cache_store(db, key, text, params, result)
    # The full check, exactly as the user saw it: the text, the prompt the model
    # was given, and the whole answer. This is what Admin Web's cards open on.
    service.record_run(
        db,
        user,
        chars=len(text),
        cached=False,
        succeeded=True,
        text=text,
        params=params,
        prompt=deepseek._prompt(
            text,
            payload.user_gender,
            payload.addressee_gender,
            payload.formality,
            payload.check_punctuation,
            payload.explanation_language,
        ),
        answer=str(result),
        model=deepseek.MODEL,
    )
    db.commit()

    # Counted after the run, so the number the app shows includes this check.
    fresh = service.text_check_quota(db, user)
    return {
        **result,
        "cached": False,
        "remaining": fresh.remaining,
        "daily_limit": fresh.daily_limit,
        "unlimited": fresh.unlimited,
    }
