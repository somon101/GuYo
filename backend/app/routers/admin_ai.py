"""Admin Web's «ИИ» section: the one DeepSeek key every AI feature uses, the
«Проверка текста» switches, and that checker's numbers and answer cache.

The key is the SAME field the AI translator writes
(LearningSettings.deepseek_api_key) -- deliberately not a second key: one
DeepSeek account, one place to change it, and both features pick it up
immediately. `PUT /admin/translation/key` still exists for the translator's
own page, but both routes write that one column.
"""

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.dates import dushanbe_day_start, dushanbe_today
from app.core.deps import get_current_admin
from app.database import get_db
from app.models.text_check import TextCheckCache, TextCheckRun
from app.schemas.text_check import MAX_TEXT_LENGTH
from app.text_check import service as text_check
from app.translation import deepseek as translator

router = APIRouter(prefix="/admin/ai", tags=["admin-ai"])


class KeyIn(BaseModel):
    api_key: str


class TextCheckSettingsIn(BaseModel):
    enabled: bool
    max_chars: int = Field(ge=1, le=MAX_TEXT_LENGTH)
    # None = no limit at all (which is what Premium gets by default);
    # 0 = nobody may check.
    free_daily_limit: int | None = Field(default=None, ge=0)
    premium_daily_limit: int | None = Field(default=None, ge=0)


class CacheEntryOut(BaseModel):
    id: int
    text: str
    hits: int
    created_at: datetime
    # The settings the answer belongs to, and a one-line summary of it, which
    # is all the admin needs to spot a bad verdict and delete it.
    params: dict
    errors: int
    ok: bool


def _key_state(db: Session) -> dict:
    key = translator.settings_row(db).deepseek_api_key
    return {
        "key_set": bool(key),
        "key_masked": f"{key[:3]}…{key[-4:]}" if key else None,
    }


def _stats(db: Session) -> dict:
    """What the checker has actually done. Counted from the run journal, so
    the numbers can never disagree with the daily limit's own count."""
    day_start = dushanbe_day_start(dushanbe_today())

    def runs(*, since: datetime | None = None, cached: bool | None = None, succeeded: bool | None = None) -> int:
        query = db.query(func.count(TextCheckRun.id))
        if since is not None:
            query = query.filter(TextCheckRun.created_at >= since)
        if cached is not None:
            query = query.filter(TextCheckRun.cached.is_(cached))
        if succeeded is not None:
            query = query.filter(TextCheckRun.succeeded.is_(succeeded))
        return query.scalar() or 0

    return {
        # Charged checks: the ones that really went to DeepSeek and answered.
        "today_checks": runs(since=day_start, cached=False, succeeded=True),
        "total_checks": runs(cached=False, succeeded=True),
        # Answered from the cache: instant and free.
        "today_cached": runs(since=day_start, cached=True),
        "total_cached": runs(cached=True),
        # DeepSeek could not answer (never charged).
        "today_failed": runs(since=day_start, cached=False, succeeded=False),
        "cache_entries": db.query(func.count(TextCheckCache.id)).scalar() or 0,
        "cache_hits": db.query(func.coalesce(func.sum(TextCheckCache.hits), 0)).scalar() or 0,
    }


def _settings_out(db: Session) -> dict:
    settings = text_check.get_settings(db)
    return {
        "enabled": settings.enabled,
        "max_chars": settings.max_chars,
        "free_daily_limit": settings.free_daily_limit,
        "premium_daily_limit": settings.premium_daily_limit,
    }


@router.get("")
def get_ai_state(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Everything the «ИИ» page shows: the key's state, the checker's
    switches, and its numbers."""
    return {"key": _key_state(db), "text_check": _settings_out(db), "stats": _stats(db)}


@router.put("/key")
def set_key(payload: KeyIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Saves (or clears) the DeepSeek key. It is the translator's own field,
    so both features start using a new key at once."""
    translator.settings_row(db).deepseek_api_key = payload.api_key.strip() or None
    db.commit()
    return _key_state(db)


@router.put("/text-check")
def set_text_check_settings(
    payload: TextCheckSettingsIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    settings = text_check.get_settings(db)
    settings.enabled = payload.enabled
    settings.max_chars = payload.max_chars
    settings.free_daily_limit = payload.free_daily_limit
    settings.premium_daily_limit = payload.premium_daily_limit
    db.commit()
    return {"text_check": _settings_out(db), "stats": _stats(db)}


@router.get("/text-check/cache")
def list_cache(
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """The cached answers, most used first -- what people actually check, and
    how much the cache is saving."""
    total = db.query(func.count(TextCheckCache.id)).scalar() or 0
    rows = (
        db.query(TextCheckCache)
        .order_by(TextCheckCache.hits.desc(), TextCheckCache.id.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return {
        "total": total,
        "entries": [
            CacheEntryOut(
                id=row.id,
                text=row.text,
                hits=row.hits or 0,
                created_at=row.created_at,
                params=row.params or {},
                errors=len((row.result or {}).get("errors") or []),
                ok=bool((row.result or {}).get("ok")),
            )
            for row in rows
        ],
    }


@router.delete("/text-check/cache/{entry_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_cache_entry(entry_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Forgets ONE cached answer: the next identical text is asked afresh.
    This is how a verdict that came out wrong is removed."""
    if not text_check.delete_cache_entry(db, entry_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Запись не найдена")
    db.commit()


@router.delete("/text-check/cache", status_code=status.HTTP_204_NO_CONTENT)
def clear_cache(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Empties the whole cache. Worth doing after the prompt changes: old
    entries stop being used by themselves (the prompt's hash is part of the
    key), but they would otherwise sit there taking up room."""
    text_check.clear_cache(db)
    db.commit()
