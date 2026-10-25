"""Universal rewards: one admin-editable list per event (duel result, streak
milestone, comeback) and the daily-goal tiers. A reward is
{"type": "xp" | "chest" | "diamonds" | "rating_points", "amount": n} or, for a
chest, {"type": "chest", "key": "gold", "amount": count}."""

from datetime import date, datetime, timezone

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.chests import service
from app.chests.service import ChestError
from app.models.chests import ChestType, DailyGoalClaim, RewardMarker, RewardRule
from app.models.user import User

REWARD_TYPES = ("xp", "chest", "diamonds", "rating_points")
RULE_KEYS = ("duel_win", "duel_draw", "duel_lose", "streak_7", "streak_30", "streak_100", "comeback")
DAILY_GOAL_KEY = "daily_goal"
MAX_REWARDS = 6
MAX_TIERS = 6

DEFAULTS: dict[str, list] = {
    "duel_win": [{"type": "xp", "amount": 50}, {"type": "chest", "key": "wood", "amount": 1}],
    "duel_draw": [{"type": "xp", "amount": 10}],
    "duel_lose": [],
    "streak_7": [{"type": "chest", "key": "wood", "amount": 1}],
    "streak_30": [{"type": "chest", "key": "silver", "amount": 1}],
    "streak_100": [{"type": "chest", "key": "gold", "amount": 1}],
    "comeback": [{"type": "xp", "amount": 20}, {"type": "chest", "key": "wood", "amount": 1}],
    DAILY_GOAL_KEY: [
        {"words": 5, "rewards": [{"type": "xp", "amount": 10}]},
        {"words": 10, "rewards": [{"type": "xp", "amount": 15}, {"type": "chest", "key": "wood", "amount": 1}]},
        {"words": 20, "rewards": [{"type": "xp", "amount": 25}, {"type": "chest", "key": "silver", "amount": 1}]},
    ],
}


def validate_rewards(db: Session, rewards) -> list[dict]:
    if not isinstance(rewards, list) or len(rewards) > MAX_REWARDS:
        raise ChestError(f"Не больше {MAX_REWARDS} наград")
    out = []
    for r in rewards:
        kind = r.get("type") if isinstance(r, dict) else None
        if kind not in REWARD_TYPES:
            raise ChestError("Неизвестная награда")
        amount = int(r.get("amount", 1))
        if not 1 <= amount <= (10 if kind == "chest" else 100_000):
            raise ChestError("Неверное количество награды")
        item = {"type": kind, "amount": amount}
        if kind == "chest":
            if db.get(ChestType, r.get("key")) is None:
                raise ChestError("Выберите сундук")
            item["key"] = r["key"]
        out.append(item)
    return out


def get_rule(db: Session, key: str) -> list:
    row = db.get(RewardRule, key)
    return row.data if row is not None else DEFAULTS[key]


def all_rules(db: Session) -> dict:
    return {k: get_rule(db, k) for k in (*RULE_KEYS, DAILY_GOAL_KEY)}


def save_rules(db: Session, payload: dict) -> dict:
    for key, data in payload.items():
        if key in RULE_KEYS:
            value = validate_rewards(db, data)
        elif key == DAILY_GOAL_KEY:
            if not isinstance(data, list) or not 1 <= len(data) <= MAX_TIERS:
                raise ChestError(f"Нужно от 1 до {MAX_TIERS} вариантов цели")
            value, seen = [], set()
            for tier in sorted(data, key=lambda t: int(t.get("words", 0))):
                words = int(tier.get("words", 0))
                if not 1 <= words <= 1000 or words in seen:
                    raise ChestError("Количество слов: от 1 до 1000, без повторов")
                seen.add(words)
                value.append({"words": words, "rewards": validate_rewards(db, tier.get("rewards", []))})
        else:
            raise ChestError("Неизвестное правило")
        row = db.get(RewardRule, key)
        if row is None:
            db.add(RewardRule(key=key, data=value))
        else:
            row.data = value
    db.flush()
    return all_rules(db)


def give(db: Session, user: User, rewards: list[dict], source: str, ref: str) -> dict:
    """Pays a reward list once per `ref`. Returns what was given:
    {"xp": n, "diamonds": n, "points": n, "chests": [keys]}. Does not commit."""
    from app.economy.service import grant_diamonds
    from app.rating import grant_rating_points
    from app.seasonpass.service import award_xp

    given = {"xp": 0, "diamonds": 0, "points": 0, "chests": []}
    for i, r in enumerate(rewards):
        key = f"{ref}:{i}"
        if r["type"] == "xp":
            given["xp"] += award_xp(db, user, source, key, r["amount"])
        elif r["type"] == "diamonds":
            given["diamonds"] += grant_diamonds(db, user, r["amount"], source, key)
        elif r["type"] == "rating_points":
            if _once(db, user, key):
                grant_rating_points(db, user, r["amount"])
                given["points"] += r["amount"]
        elif r["type"] == "chest":
            for n in range(r["amount"]):
                if service.grant_chest(db, user, r["key"], source, f"{key}:{n}", force=True):
                    given["chests"].append(r["key"])
    return given


def _once(db: Session, user: User, key: str) -> bool:
    try:
        with db.begin_nested():
            db.add(RewardMarker(user_id=user.id, key=key))
            db.flush()
    except IntegrityError:
        return False
    return True


# ---- daily goal -------------------------------------------------------------

def daily_tiers(db: Session) -> list[dict]:
    return get_rule(db, DAILY_GOAL_KEY)


def earn_daily_goal(db: Session, user: User, done: int, today: date) -> bool:
    """Marks the picked tier as earned once it is filled (once per day per tier). Nothing is
    paid here: the person takes the reward with «Получить». True on the call that earned it."""
    tier = next((t for t in daily_tiers(db) if t["words"] == user.daily_goal), None)
    if tier is None or done < tier["words"]:
        return False
    try:
        with db.begin_nested():
            db.add(DailyGoalClaim(user_id=user.id, day=today, words=tier["words"]))
            db.flush()
    except IntegrityError:
        return False
    return True


def waiting_claim(db: Session, user: User, today: date) -> DailyGoalClaim | None:
    """Today's earned-but-not-taken reward of the picked tier."""
    return (
        db.query(DailyGoalClaim)
        .filter_by(user_id=user.id, day=today, words=user.daily_goal)
        .filter(DailyGoalClaim.claimed_at.is_(None))
        .first()
    )


def claim_goal(db: Session, user: User, claim_id: int) -> dict:
    """Pays an earned daily-goal reward, once."""
    claim = (
        db.query(DailyGoalClaim)
        .filter(DailyGoalClaim.id == claim_id, DailyGoalClaim.user_id == user.id)
        .with_for_update()
        .first()
    )
    if claim is None:
        raise ChestError("Награда не найдена")
    if claim.claimed_at is not None:
        raise ChestError("Награда уже получена")
    tier = next((t for t in daily_tiers(db) if t["words"] == claim.words), None)
    rewards_list = tier["rewards"] if tier else []
    claim.claimed_at = datetime.now(timezone.utc)
    db.flush()
    return give(db, user, rewards_list, "daily_goal", f"goal:{claim.day.isoformat()}:{claim.words}")


def notify_unclaimed(db: Session, today: date) -> int:
    """Rewards earned on an earlier day and still not taken go to the person's notifications,
    with a «Получить» button. Once per reward."""
    from app.notifications.service import send_notification

    sent = 0
    rows = (
        db.query(DailyGoalClaim)
        .filter(DailyGoalClaim.day < today, DailyGoalClaim.claimed_at.is_(None), DailyGoalClaim.notified.is_(False))
        .limit(500)
        .all()
    )
    for claim in rows:
        user = db.get(User, claim.user_id)
        claim.notified = True
        if user is None:
            continue
        tier = next((t for t in daily_tiers(db) if t["words"] == claim.words), None)
        title, body = _TEXTS.get(user.ui_language, _TEXTS["ru"])
        send_notification(
            db, user, body.format(words=claim.words), title=title, source="goal_reward",
            dedupe_key=f"goal-claim:{claim.id}", action=f"claim_goal:{claim.id}", payload=tier["rewards"] if tier else [],
        )
        sent += 1
    return sent


_TEXTS = {
    "ru": ("Награда за цель дня ждёт вас", "Вы выполнили цель ({words} слов). Заберите подарок!"),
    "en": ("Your daily goal reward is waiting", "You reached your goal ({words} words). Take your gift!"),
    "tg": ("Мукофоти ҳадафи рӯз мунтазир аст", "Шумо ҳадафро иҷро кардед ({words} калима). Тӯҳфаро гиред!"),
    "uz": ("Kun maqsadi mukofoti sizni kutmoqda", "Siz maqsadni bajardingiz ({words} so'z). Sovg'ani oling!"),
    "zh": ("每日目标奖励在等你", "你完成了目标（{words}个词）。快来领取礼物！"),
}
