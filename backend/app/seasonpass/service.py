"""The season pass: XP, levels, rewards, weekly tasks and the monthly seasons
it runs in. See app/models/season_pass.py for the shape of a definition.

Everything is derived from two small ledgers -- PassXpEvent (XP awards, each
at most once) and PassClaim (rewards taken) -- so a repeated request can
never double-award or double-claim."""

import copy
from datetime import date, datetime, timedelta

from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dates import DUSHANBE_TZ, utc_now
from app.models.rating import SEASON_ACTIVE, SEASON_COMPLETED, SEASON_SCHEDULED, Season
from app.models.season_pass import PassClaim, PassSettings, PassTemplate, PassXpEvent, SeasonPass
from app.models.user import User

# What a weekly task counts: the `source` of the XP events.
METRICS = ("word", "lesson", "review", "quest", "streak")
REWARD_TYPES = ("rating_points", "premium_days", "streak_freeze", "badge", "title")
LEVEL_MAX = 100


class PassError(Exception):
    """A user-facing refusal (the message is shown as is)."""


# --- Settings and the default definition ------------------------------------


def get_pass_settings(db: Session) -> PassSettings:
    settings = db.get(PassSettings, 1)
    if settings is None:
        settings = PassSettings(id=1)
        db.add(settings)
        db.flush()
    return settings


def default_definition() -> dict:
    """30 levels at 80 XP. Free: rating points, a Premium day every 5th level;
    Premium: more points, a few days of Premium on the 5th levels. A title at
    level 10, a diamond badge (Premium) at 20 and the season's crown badge at
    30 (with a title for Premium)."""
    levels = []
    for n in range(1, 31):
        milestone = n % 5 == 0
        free = (
            {"type": "premium_days", "amount": 1 if n < 30 else 3}
            if milestone
            else {"type": "rating_points", "amount": 20}
        )
        premium = (
            {"type": "premium_days", "amount": 3 if n < 30 else 7}
            if milestone
            else {"type": "rating_points", "amount": 50}
        )
        if n == 10:
            free = {"type": "title", "amount": 1, "text": "Знаток слов", "text_tg": "Донишманди калимаҳо", "text_uz": "So‘z bilimdoni"}
        if n == 20:
            premium = {"type": "badge", "amount": 1, "key": "diamond", "text": "Бриллиант сезона", "text_tg": "Алмоси мавсим", "text_uz": "Mavsum brilliant"}
        if n == 30:
            free = {"type": "badge", "amount": 1, "key": "crown", "text": "Чемпион сезона", "text_tg": "Қаҳрамони мавсим", "text_uz": "Mavsum chempioni"}
            premium = {"type": "title", "amount": 1, "text": "Мастер слов", "text_tg": "Устоди калимаҳо", "text_uz": "So‘z ustasi"}
        levels.append({"level": n, "xp": 80, "free": free, "premium": premium})
    tasks = [
        {"id": "words", "metric": "word", "target": 5, "xp": 50},
        {"id": "lessons", "metric": "lesson", "target": 3, "xp": 50},
        {"id": "streak", "metric": "streak", "target": 5, "xp": 60},
        {"id": "quests", "metric": "quest", "target": 3, "xp": 40},
        {"id": "review", "metric": "review", "target": 20, "xp": 40},
    ]
    return {"levels": levels, "tasks": tasks}


def validate_definition(definition: dict) -> dict:
    """Checks and normalises a definition from the admin; raises PassError."""
    levels = definition.get("levels")
    tasks = definition.get("tasks", [])
    if not isinstance(levels, list) or not levels:
        raise PassError("Нужен хотя бы один уровень")
    if len(levels) > LEVEL_MAX:
        raise PassError(f"Не больше {LEVEL_MAX} уровней")
    out_levels = []
    for i, lv in enumerate(levels, start=1):
        xp = int(lv.get("xp", 0))
        if xp < 1:
            raise PassError(f"Уровень {i}: нужно больше 0 XP")
        out_levels.append(
            {"level": i, "xp": xp, "free": _reward(lv.get("free"), i), "premium": _reward(lv.get("premium"), i)}
        )
    out_tasks = []
    seen = set()
    for t in tasks:
        task_id = str(t.get("id") or "").strip()
        if not task_id or task_id in seen:
            raise PassError("У каждого задания свой непустой id")
        seen.add(task_id)
        if t.get("metric") not in METRICS:
            raise PassError(f"Задание «{task_id}»: неизвестная метрика")
        target, xp = int(t.get("target", 0)), int(t.get("xp", 0))
        if target < 1 or xp < 0:
            raise PassError(f"Задание «{task_id}»: цель должна быть больше 0")
        out_tasks.append({"id": task_id, "metric": t["metric"], "target": target, "xp": xp})
    return {"levels": out_levels, "tasks": out_tasks}


def _reward(value: dict | None, level: int) -> dict | None:
    if not value or not value.get("type"):
        return None
    if value["type"] not in REWARD_TYPES:
        raise PassError(f"Уровень {level}: неизвестная награда")
    if value["type"] in ("badge", "title"):
        from app.seasonpass.cosmetics import BADGE_KEYS

        text = str(value.get("text") or "").strip()
        if not text:
            raise PassError(f"Уровень {level}: у значка или титула нужно название")
        out = {"type": value["type"], "amount": 1, "text": text[:120]}
        for lang in ("text_tg", "text_uz"):
            if str(value.get(lang) or "").strip():
                out[lang] = str(value[lang]).strip()[:120]
        if value["type"] == "badge":
            if value.get("key") not in BADGE_KEYS:
                raise PassError(f"Уровень {level}: выберите вид значка")
            out["key"] = value["key"]
        return out
    amount = int(value.get("amount", 0))
    if amount < 1:
        raise PassError(f"Уровень {level}: количество награды должно быть больше 0")
    return {"type": value["type"], "amount": amount}


# --- Templates and a season's copy -------------------------------------------


def default_template(db: Session) -> PassTemplate:
    template = db.query(PassTemplate).filter(PassTemplate.is_default.is_(True)).first()
    if template is None:
        template = db.query(PassTemplate).order_by(PassTemplate.id).first()
    if template is None:
        template = PassTemplate(name="Стандартный", is_default=True, definition=default_definition())
        db.add(template)
        db.flush()
    return template


def season_pass(db: Session, season: Season) -> SeasonPass:
    """The season's own definition, copied from the default template the
    first time it is needed."""
    sp = db.query(SeasonPass).filter(SeasonPass.season_id == season.id).first()
    if sp is None:
        template = default_template(db)
        sp = SeasonPass(season_id=season.id, template_id=template.id, definition=copy.deepcopy(template.definition))
        db.add(sp)
        db.flush()
    return sp


def apply_template(db: Session, season: Season, template: PassTemplate) -> SeasonPass:
    """Replaces the season's definition with a fresh copy of the template."""
    sp = season_pass(db, season)
    sp.template_id = template.id
    sp.definition = copy.deepcopy(template.definition)
    db.flush()
    return sp


# --- XP ----------------------------------------------------------------------


def _active_season(db: Session) -> Season | None:
    return db.query(Season).filter(Season.status == SEASON_ACTIVE).first()


def xp_for(settings: PassSettings, source: str) -> int:
    return {
        "word": settings.xp_word,
        "lesson": settings.xp_lesson,
        "review": settings.xp_review,
        "quest": settings.xp_quest,
        "streak": settings.xp_streak,
    }.get(source, 0)


def award_xp(db: Session, user: User, source: str, key: str, amount: int | None = None) -> int:
    """Awards season XP once per (user, season, key). Returns what was
    awarded (0 when there is no live season, nothing is worth XP, or it was
    awarded already). Never raises and never disturbs the caller's
    transaction. Does not commit."""
    try:
        season = _active_season(db)
        if season is None:
            return 0
        if amount is None:
            amount = xp_for(get_pass_settings(db), source)
        if amount <= 0:
            return 0
        try:
            with db.begin_nested():
                db.add(PassXpEvent(user_id=user.id, season_id=season.id, source=source, amount=amount, dedupe_key=key))
                db.flush()
        except IntegrityError:
            return 0
        return amount
    except Exception:  # XP is a bonus: a failure here must never lose a lesson
        return 0


def total_xp(db: Session, user_id: int, season_id: int) -> int:
    return (
        db.query(func.coalesce(func.sum(PassXpEvent.amount), 0))
        .filter(PassXpEvent.user_id == user_id, PassXpEvent.season_id == season_id)
        .scalar()
        or 0
    )


def level_for_xp(levels: list[dict], xp: int) -> tuple[int, int, int | None]:
    """(reached level, XP into the next level, that level's cost or None at
    the top)."""
    reached, left = 0, xp
    for lv in levels:
        if left < lv["xp"]:
            return reached, left, lv["xp"]
        left -= lv["xp"]
        reached = lv["level"]
    return reached, 0, None


# --- Weeks -------------------------------------------------------------------


def week_bounds(now: datetime, season: Season) -> tuple[date, datetime, datetime]:
    """The Monday-based Dushanbe week containing `now`, cut to the season:
    (week start date, start moment, end moment)."""
    local = now.astimezone(DUSHANBE_TZ)
    monday = local.date() - timedelta(days=local.weekday())
    start = datetime.combine(monday, datetime.min.time(), tzinfo=DUSHANBE_TZ)
    end = start + timedelta(days=7)
    start = max(start, season.starts_at)
    if season.ends_at is not None:
        end = min(end, season.ends_at)
    return monday, start, end


def task_progress(db: Session, user_id: int, season: Season, metric: str, start: datetime, end: datetime) -> int:
    return (
        db.query(func.count(PassXpEvent.id))
        .filter(
            PassXpEvent.user_id == user_id,
            PassXpEvent.season_id == season.id,
            PassXpEvent.source == metric,
            PassXpEvent.created_at >= start,
            PassXpEvent.created_at < end,
        )
        .scalar()
        or 0
    )


# --- The user's view and claiming -----------------------------------------------


def _claims(db: Session, user_id: int, season_id: int) -> set[tuple[str, str]]:
    return {
        (k, r)
        for k, r in db.query(PassClaim.kind, PassClaim.ref).filter(
            PassClaim.user_id == user_id, PassClaim.season_id == season_id
        )
    }


def _has_premium(db: Session, user: User) -> bool:
    from app.premium.service import effective_premium_until

    return effective_premium_until(db, user) is not None


def _premium_enabled(db: Session) -> bool:
    from app.premium.service import get_premium_settings

    return bool(get_premium_settings(db).premium_enabled)


def user_state(db: Session, user: User) -> dict | None:
    """Everything the pass screen shows; None while no season is live."""
    ensure_monthly_seasons(db)
    from app.rating import sync_season_states

    sync_season_states(db)
    season = _active_season(db)
    if season is None:
        return None
    sp = season_pass(db, season)
    levels = sp.definition["levels"]
    xp = total_xp(db, user.id, season.id)
    reached, into, cost = level_for_xp(levels, xp)
    claimed = _claims(db, user.id, season.id)
    has_premium = _has_premium(db, user)

    def lane(lv: dict, kind: str) -> dict | None:
        reward = lv.get(kind)
        if not reward:
            return None
        taken = (kind, str(lv["level"])) in claimed
        unlocked = lv["level"] <= reached
        allowed = kind == "free" or has_premium
        from app.seasonpass.cosmetics import label_for

        return {
            **reward,
            "text": label_for(reward, user.ui_language) if reward.get("text") else None,
            "claimed": taken,
            "claimable": unlocked and allowed and not taken,
            "locked_by_premium": kind == "premium" and not has_premium,
        }

    now = utc_now()
    monday, start, end = week_bounds(now, season)
    tasks = []
    for t in sp.definition.get("tasks", []):
        progress = task_progress(db, user.id, season, t["metric"], start, end)
        taken = ("task", f"{monday.isoformat()}:{t['id']}") in claimed
        tasks.append(
            {
                "id": t["id"],
                "metric": t["metric"],
                "target": t["target"],
                "xp": t["xp"],
                "progress": min(progress, t["target"]),
                "claimed": taken,
                "claimable": progress >= t["target"] and not taken,
            }
        )
    return {
        "season_id": season.id,
        "season_name": season.name,
        "season_name_tg": season.name_tg,
        "season_name_uz": season.name_uz,
        "starts_at": season.starts_at,
        "ends_at": season.ends_at,
        "xp": xp,
        "level": reached,
        "xp_into_level": into,
        "xp_for_next": cost,
        "is_premium": has_premium,
        "premium_enabled": _premium_enabled(db),
        "streak_freezes": user.streak_freezes or 0,
        "levels": [
            {"level": lv["level"], "xp": lv["xp"], "free": lane(lv, "free"), "premium": lane(lv, "premium")}
            for lv in levels
        ],
        "week": {"starts_on": monday, "ends_at": end, "tasks": tasks},
    }


def _give(db: Session, user: User, reward: dict, note: str, season: Season | None = None) -> None:
    if reward["type"] == "rating_points":
        from app.rating import grant_rating_points

        grant_rating_points(db, user, reward["amount"])
    elif reward["type"] == "streak_freeze":
        user.streak_freezes = (user.streak_freezes or 0) + reward["amount"]
        db.flush()
    elif reward["type"] in ("badge", "title"):
        from app.seasonpass.cosmetics import grant

        grant(db, user, reward, season)
    elif reward["type"] == "premium_days":
        from app.premium.service import grant_premium

        grant_premium(db, user, reward["amount"], note=note, source="season_pass", reason="Награда пропуска сезона!")


def _record_claim(db: Session, user: User, season: Season, kind: str, ref: str) -> None:
    try:
        with db.begin_nested():
            db.add(PassClaim(user_id=user.id, season_id=season.id, kind=kind, ref=ref))
            db.flush()
    except IntegrityError:
        raise PassError("Награда уже получена") from None


def claim_level(db: Session, user: User, level: int, track: str) -> dict:
    """Takes a level's reward. Premium rewards need Premium right now and
    can be taken for any level already reached, also after the fact."""
    if track not in ("free", "premium"):
        raise PassError("Неизвестная дорожка")
    season = _active_season(db)
    if season is None:
        raise PassError("Сейчас нет активного сезона")
    sp = season_pass(db, season)
    lv = next((x for x in sp.definition["levels"] if x["level"] == level), None)
    reward = lv.get(track) if lv else None
    if lv is None or not reward:
        raise PassError("На этом уровне нет награды")
    reached, _, _ = level_for_xp(sp.definition["levels"], total_xp(db, user.id, season.id))
    if level > reached:
        raise PassError("Уровень ещё не достигнут")
    if track == "premium" and not _has_premium(db, user):
        raise PassError("Эта награда доступна с Premium")
    if reward["type"] == "streak_freeze":
        cap = get_pass_settings(db).freeze_cap
        if (user.streak_freezes or 0) + reward["amount"] > cap:
            raise PassError(f"Запас заморозок полон (не больше {cap}). Награду можно забрать позже")
    _record_claim(db, user, season, track, str(level))
    _give(db, user, reward, f"Пропуск сезона «{season.name}», уровень {level}", season)
    return reward


def claim_task(db: Session, user: User, task_id: str) -> int:
    """Takes a finished weekly task's XP (current week only); returns it."""
    season = _active_season(db)
    if season is None:
        raise PassError("Сейчас нет активного сезона")
    sp = season_pass(db, season)
    task = next((t for t in sp.definition.get("tasks", []) if t["id"] == task_id), None)
    if task is None:
        raise PassError("Задание не найдено")
    monday, start, end = week_bounds(utc_now(), season)
    if task_progress(db, user.id, season, task["metric"], start, end) < task["target"]:
        raise PassError("Задание ещё не выполнено")
    ref = f"{monday.isoformat()}:{task_id}"
    _record_claim(db, user, season, "task", ref)
    awarded = award_xp(db, user, "task", f"task:{ref}", task["xp"])
    return awarded


# --- Monthly seasons ---------------------------------------------------------

_MONTHS_RU = ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"]
_MONTHS_TG = ["Январ", "Феврал", "Март", "Апрел", "Май", "Июн", "Июл", "Август", "Сентябр", "Октябр", "Ноябр", "Декабр"]
_MONTHS_UZ = ["Yanvar", "Fevral", "Mart", "Aprel", "May", "Iyun", "Iyul", "Avgust", "Sentabr", "Oktabr", "Noyabr", "Dekabr"]


def _month_start(year: int, month: int) -> datetime:
    return datetime(year, month, 1, tzinfo=DUSHANBE_TZ)


def ensure_monthly_seasons(db: Session, now: datetime | None = None) -> int:
    """Makes sure the current and the next calendar month (Dushanbe time)
    each have a season, creating the missing ones. A month that already
    overlaps another season is left alone. Returns how many were created.
    Commits."""
    from app.rating.service import assert_season_period_free

    if not get_pass_settings(db).auto_monthly_seasons:
        return 0
    local = (now or utc_now()).astimezone(DUSHANBE_TZ)
    created = 0
    year, month = local.year, local.month
    for _ in range(2):
        starts = _month_start(year, month)
        ny, nm = (year + 1, 1) if month == 12 else (year, month + 1)
        ends = _month_start(ny, nm)
        exists = (
            db.query(Season.id)
            .filter(Season.status != SEASON_COMPLETED, Season.starts_at < ends, Season.ends_at > starts)
            .first()
        )
        if exists is None:
            try:
                assert_season_period_free(db, starts_at=starts, ends_at=ends)
            except ValueError:
                pass
            else:
                db.add(
                    Season(
                        name=f"{_MONTHS_RU[month - 1]} {year}",
                        name_tg=f"{_MONTHS_TG[month - 1]} {year}",
                        name_uz=f"{_MONTHS_UZ[month - 1]} {year}",
                        starts_at=starts,
                        ends_at=ends,
                        status=SEASON_SCHEDULED,
                    )
                )
                created += 1
        year, month = ny, nm
    if created:
        db.commit()
    return created
