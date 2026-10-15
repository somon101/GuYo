"""Everything «Проверка текста» decides, in one place: the admin's settings,
how many checks a user has left today, the answer cache and the run journal.

The app's endpoint (app/routers/text_check.py) and Admin Web's «ИИ» section
both read this module, so there is only ever ONE definition of "may this
person check a text right now" and ONE cache implementation.

The order of a check, and why it is that order:

1. The feature is on, the text is short enough, and a free check is left --
   all decided BEFORE DeepSeek is called, so a user over their limit never
   costs anything.
2. The cache is consulted (exact match only -- see app/models/text_check.py
   for why a near match is never reused).
3. On a cache hit the run is journalled with `cached=True`: it is counted for
   the statistics, but NOT against the daily limit, because it cost nothing.
4. On a miss DeepSeek is asked; a successful answer is stored in the cache and
   journalled with `succeeded=True` (a real, charged check), while a failure
   is journalled with `succeeded=False` and never counted either.
"""

import hashlib
import logging
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dates import dushanbe_day_start, dushanbe_today
from app.models.text_check import MAX_STORED_TEXT, TextCheckCache, TextCheckRun, TextCheckSettings
from app.models.user import User
from app.premium import service as premium
from app.text_check import deepseek

log = logging.getLogger(__name__)

# The settings keys that change an answer. Kept here as the one list both the
# fingerprint and the stored cache row are built from.
PARAM_KEYS = ("user_gender", "addressee_gender", "formality", "check_punctuation", "explanation_language")


def get_settings(db: Session) -> TextCheckSettings:
    """The single admin row, created lazily with its defaults on first read --
    the same idiom as PremiumSettings and every other settings row here."""
    settings = db.get(TextCheckSettings, 1)
    if settings is None:
        settings = TextCheckSettings(id=1)
        db.add(settings)
        db.flush()
    return settings


def normalize(text: str) -> str:
    """The only transformations a cache key is allowed to make: the spaces
    around the message, and case.

    Nothing else, on purpose. Internal spaces, a missing full stop, one wrong
    letter and word order are all things this tool exists to point out, so
    treating two texts that differ in them as "the same question" would hand
    out the wrong verdict -- and the wrong verdict would be cached for
    everyone.
    """
    return text.strip().casefold()


def fingerprint(text: str, params: dict) -> str:
    """The cache key: the prompt's own hash, the model, every answer-changing
    setting, and the normalized text.

    Hashing the prompt means editing it (or changing the model) retires every
    cached answer by itself -- an old verdict can never be served under new
    rules, and nothing has to be remembered or cleaned by hand.
    """
    parts = [deepseek.PROMPT_VERSION, deepseek.MODEL]
    parts += [str(params.get(key) if params.get(key) is not None else "") for key in PARAM_KEYS]
    parts.append(normalize(text))
    return hashlib.sha256("\n".join(parts).encode("utf-8")).hexdigest()


def cache_lookup(db: Session, key: str) -> TextCheckCache | None:
    return db.query(TextCheckCache).filter(TextCheckCache.fingerprint == key).first()


def cache_store(db: Session, key: str, text: str, params: dict, result: dict) -> TextCheckCache | None:
    """Remembers an answer. Returns the stored row, or the row that won a race
    with a simultaneous identical request (in which case this one is dropped --
    both callers get the same answer anyway)."""
    entry = TextCheckCache(
        fingerprint=key,
        text=normalize(text)[:MAX_STORED_TEXT],
        params={k: params.get(k) for k in PARAM_KEYS},
        result=result,
    )
    try:
        # A savepoint, so losing the race rolls back only this insert and
        # never the run row the caller is about to write.
        with db.begin_nested():
            db.add(entry)
    except IntegrityError:
        return cache_lookup(db, key)
    return entry


def cache_hit(db: Session, entry: TextCheckCache) -> dict:
    """Counts one serving of a cached answer and returns it."""
    entry.hits = (entry.hits or 0) + 1
    return entry.result


def clear_cache(db: Session) -> int:
    """Deletes every cached answer (Admin Web's «Очистить кеш»). Returns how
    many rows went -- the number the admin sees in the confirmation."""
    removed = db.query(TextCheckCache).delete()
    return removed or 0


def delete_cache_entry(db: Session, entry_id: int) -> bool:
    """Forgets one cached answer, so the next identical text is asked afresh.
    This is how a bad verdict is removed without touching anything else."""
    entry = db.get(TextCheckCache, entry_id)
    if entry is None:
        return False
    db.delete(entry)
    return True


@dataclass
class TextCheckQuota:
    """Where a user stands against the checker's limit right now. A limit of
    None, or `unlimited`, means they can check as much as they like."""

    is_premium: bool
    unlimited: bool
    daily_limit: int | None
    daily_used: int
    next_day_starts_at: datetime

    @property
    def remaining(self) -> int | None:
        if self.unlimited or self.daily_limit is None:
            return None
        return max(0, self.daily_limit - self.daily_used)

    @property
    def blocked(self) -> bool:
        return not self.unlimited and self.daily_limit is not None and self.daily_used >= self.daily_limit


def text_check_quota(db: Session, user: User) -> TextCheckQuota:
    """Free and Premium have their own daily allowance (Admin Web's «ИИ»),
    and `users.text_check_unlimited` overrides both for one person at a time.

    Only successful, uncached checks are counted -- see this module's own
    opening note. Days are Asia/Dushanbe calendar days, the same boundary
    lessons and quests reset on."""
    settings = get_settings(db)
    unlimited = bool(user.text_check_unlimited) or not settings.enabled
    # The master-switch-aware read, the same one every other "is this person
    # Premium right now" surface uses: while the Premium system is switched
    # off in Admin Web, nobody counts as Premium here either, and everyone
    # gets the free allowance (which is what keeps the limit meaningful as an
    # anti-abuse guard rather than a paid gate).
    is_premium = premium.effective_premium_until(db, user) is not None
    if unlimited:
        daily_limit = None
    else:
        daily_limit = settings.premium_daily_limit if is_premium else settings.free_daily_limit

    today = dushanbe_today()
    day_start = dushanbe_day_start(today)
    used = (
        db.query(func.count(TextCheckRun.id))
        .filter(
            TextCheckRun.user_id == user.id,
            TextCheckRun.created_at >= day_start,
            TextCheckRun.succeeded.is_(True),
            TextCheckRun.cached.is_(False),
        )
        .scalar()
        or 0
    )
    return TextCheckQuota(
        is_premium=is_premium,
        unlimited=unlimited,
        daily_limit=daily_limit,
        daily_used=used,
        next_day_starts_at=next_day_start(today),
    )


def next_day_start(today) -> datetime:
    """When today's allowance is replaced by tomorrow's -- the next Dushanbe
    midnight, the same instant every other daily counter in the app resets."""
    return dushanbe_day_start(today + timedelta(days=1))


class TextCheckLimitReached(Exception):
    """Raised by check_quota; its message is shown to the user as is."""


def check_quota(db: Session, user: User) -> TextCheckQuota:
    quota = text_check_quota(db, user)
    if not quota.blocked:
        return quota
    message = (
        f"Лимит проверок текста на сегодня исчерпан: {quota.daily_used} из {quota.daily_limit}. "
        "Проверки можно будет сделать завтра."
    )
    if not quota.is_premium:
        message += " С GuYo Premium — без ограничений."
    raise TextCheckLimitReached(message)


def record_run(
    db: Session,
    user: User,
    *,
    chars: int,
    cached: bool,
    succeeded: bool,
    text: str | None = None,
    prompt: str | None = None,
    answer: str | None = None,
    params: dict | None = None,
    model: str | None = None,
) -> None:
    """Journals one check -- the whole check, not just that it happened.

    The text, the prompt and the answer are stored WITH the run (see
    app/models/text_check.py's TextCheckRun): Admin Web shows them as cards, and a
    later "why did it answer that" is unanswerable without the prompt. The account's
    own name travels with the row so a card stays readable after an account is gone.

    Commits nothing: the caller owns the transaction."""
    db.add(
        TextCheckRun(
            user_id=user.id,
            user_login=user.login,
            chars=chars,
            cached=cached,
            succeeded=succeeded,
            text=text,
            prompt=prompt,
            answer=answer,
            params=params,
            model=model,
        )
    )


def api_key(db: Session) -> str:
    """The DeepSeek key, from the SAME settings row Admin Web's «ИИ-перевод»
    section writes (LearningSettings.deepseek_api_key) -- one key for every AI
    feature in the project, nothing hardcoded."""
    from app.translation.deepseek import settings_row

    return (settings_row(db).deepseek_api_key or "").strip()
