"""Weekly friend duels: two friends, one week, whoever earns more season XP wins."""

import logging
from datetime import date, datetime, timedelta

from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from app.core.dates import DUSHANBE_TZ, dushanbe_today
from app.models.duel import ACTIVE, CANCELLED, DECLINED, FINISHED, PENDING, Duel
from app.models.friendship import Friendship
from app.models.season_pass import PassXpEvent
from app.models.user import User
from app.core.storage import url_for_key
from app.notifications.service import send_notification
from app.progress.stats import week_start
from app.seasonpass.service import PassError, award_xp, get_pass_settings

logger = logging.getLogger(__name__)


class DuelError(PassError):
    pass


_TEXTS = {
    "challenge": {
        "ru": ("Вызов на дуэль", "{name} вызывает вас на дуэль недели: кто наберёт больше XP"),
        "tg": ("Даъват ба дуэл", "{name} шуморо ба дуэли ҳафта даъват мекунад: кӣ XP бештар мегирад"),
        "uz": ("Duelga taklif", "{name} sizni hafta duelida chaqirmoqda: kim ko'proq XP yig'adi"),
        "en": ("Duel challenge", "{name} challenges you to a week duel: who earns more XP"),
    },
    "accepted": {
        "ru": ("Дуэль началась", "{name} принял(а) вызов. Дуэль идёт до конца недели"),
        "tg": ("Дуэл оғоз шуд", "{name} даъватро қабул кард. Дуэл то охири ҳафта давом мекунад"),
        "uz": ("Duel boshlandi", "{name} taklifni qabul qildi. Duel hafta oxirigacha davom etadi"),
        "en": ("The duel has begun", "{name} accepted. The duel runs until the end of the week"),
    },
    "overtaken": {
        "ru": ("Вас обогнали", "{name} вырвался(лась) вперёд в дуэли. Самое время позаниматься!"),
        "tg": ("Шуморо пеш гирифтанд", "{name} дар дуэл пеш гузашт. Вақти машғул шудан аст!"),
        "uz": ("Sizni quvib o'tishdi", "{name} duelda oldinga chiqdi. Mashq qilish payti!"),
        "en": ("You were overtaken", "{name} pulled ahead in the duel. Time to study!"),
    },
    "won": {
        "ru": ("Вы выиграли дуэль!", "Победа над {name}: {mine} против {theirs} XP. Бонус: +{bonus} XP"),
        "tg": ("Шумо дуэлро бурдед!", "Ғалаба бар {name}: {mine} зидди {theirs} XP. Бонус: +{bonus} XP"),
        "uz": ("Duelda g'alaba!", "{name} ustidan g'alaba: {mine} va {theirs} XP. Bonus: +{bonus} XP"),
        "en": ("You won the duel!", "You beat {name}: {mine} vs {theirs} XP. Bonus: +{bonus} XP"),
    },
    "lost": {
        "ru": ("Дуэль окончена", "{name} оказался(лась) сильнее: {theirs} против {mine} XP. Реванш на следующей неделе!"),
        "tg": ("Дуэл ба охир расид", "{name} қавитар баромад: {theirs} зидди {mine} XP. Реванш ҳафтаи оянда!"),
        "uz": ("Duel tugadi", "{name} kuchliroq chiqdi: {theirs} va {mine} XP. Keyingi hafta revanj!"),
        "en": ("The duel is over", "{name} was stronger: {theirs} vs {mine} XP. Rematch next week!"),
    },
    "draw": {
        "ru": ("Дуэль: ничья", "С {name} вы набрали поровну: {mine} XP. Реванш?"),
        "tg": ("Дуэл: дуранг", "Бо {name} баробар ҷамъ кардед: {mine} XP. Реванш?"),
        "uz": ("Duel: durang", "{name} bilan teng yig'dingiz: {mine} XP. Revanj?"),
        "en": ("Duel: a draw", "You and {name} earned the same: {mine} XP. Rematch?"),
    },
}


def _notify(db: Session, user: User, kind: str, key: str, **fields) -> None:
    try:
        lang = user.ui_language if user.ui_language in ("ru", "tg", "uz", "en") else "ru"
        title, body = _TEXTS[kind][lang]
        send_notification(db, user, body.format(**fields), title=title, source="duel", dedupe_key=key)
    except Exception:  # a message is a courtesy; never fail the action over it
        logger.exception("duel notification failed")


def _bounds(duel: Duel) -> tuple[datetime, datetime]:
    start = datetime.combine(duel.week_start, datetime.min.time(), tzinfo=DUSHANBE_TZ)
    return start, start + timedelta(days=7)


def scores(db: Session, duel: Duel) -> tuple[int, int]:
    """(challenger XP, opponent XP) earned during the duel's week."""
    start, end = _bounds(duel)
    rows = dict(
        db.query(PassXpEvent.user_id, func.sum(PassXpEvent.amount))
        .filter(
            PassXpEvent.user_id.in_([duel.challenger_id, duel.opponent_id]),
            PassXpEvent.created_at >= start,
            PassXpEvent.created_at < end,
        )
        .group_by(PassXpEvent.user_id)
        .all()
    )
    return int(rows.get(duel.challenger_id, 0)), int(rows.get(duel.opponent_id, 0))


def _is_friend(db: Session, a: int, b: int) -> bool:
    return db.query(Friendship.id).filter(Friendship.user_id == a, Friendship.friend_id == b).first() is not None


def _busy(db: Session, user_id: int) -> bool:
    return (
        db.query(Duel.id)
        .filter(
            Duel.status.in_([PENDING, ACTIVE]),
            or_(Duel.challenger_id == user_id, Duel.opponent_id == user_id),
            Duel.week_start == week_start(dushanbe_today()),
        )
        .first()
        is not None
    )


def _name(user: User) -> str:
    return user.login


def challenge(db: Session, user: User, friend_id: int) -> Duel:
    if not get_pass_settings(db).duels_enabled:
        raise DuelError("Дуэли сейчас отключены")
    if friend_id == user.id or not _is_friend(db, user.id, friend_id):
        raise DuelError("Вызвать можно только друга")
    friend = db.get(User, friend_id)
    if friend is None or friend.deleted_at is not None:
        raise DuelError("Вызвать можно только друга")
    if _busy(db, user.id) or _busy(db, friend_id):
        raise DuelError("У вас или у друга уже есть дуэль на эту неделю")
    duel = Duel(challenger_id=user.id, opponent_id=friend_id, week_start=week_start(dushanbe_today()))
    db.add(duel)
    db.flush()
    _notify(db, friend, "challenge", f"duel-challenge:{duel.id}", name=_name(user))
    return duel


def _mine(db: Session, user: User, duel_id: int) -> Duel:
    duel = db.get(Duel, duel_id)
    if duel is None or user.id not in (duel.challenger_id, duel.opponent_id):
        raise DuelError("Дуэль не найдена")
    return duel


def accept(db: Session, user: User, duel_id: int) -> Duel:
    duel = _mine(db, user, duel_id)
    if duel.opponent_id != user.id or duel.status != PENDING:
        raise DuelError("Этот вызов уже нельзя принять")
    if duel.week_start != week_start(dushanbe_today()):
        duel.status = CANCELLED
        db.flush()
        raise DuelError("Этот вызов уже устарел")
    duel.status = ACTIVE
    db.flush()
    challenger = db.get(User, duel.challenger_id)
    if challenger:
        _notify(db, challenger, "accepted", f"duel-accepted:{duel.id}", name=_name(user))
    return duel


def decline(db: Session, user: User, duel_id: int) -> Duel:
    """The opponent turns a challenge down, or the challenger takes it back."""
    duel = _mine(db, user, duel_id)
    if duel.status != PENDING:
        raise DuelError("Этот вызов уже нельзя отклонить")
    duel.status = DECLINED if duel.opponent_id == user.id else CANCELLED
    db.flush()
    return duel


def _side(duel: Duel, user: User) -> tuple[int, int]:
    return (1, 0) if duel.challenger_id == user.id else (0, 1)


def state(db: Session, user: User) -> dict:
    """Current-week duel (if any) with scores, plus the recent finished ones."""
    monday = week_start(dushanbe_today())
    mine = or_(Duel.challenger_id == user.id, Duel.opponent_id == user.id)
    current = (
        db.query(Duel)
        .filter(mine, Duel.week_start == monday, Duel.status.in_([PENDING, ACTIVE]))
        .order_by(Duel.id.desc())
        .first()
    )
    recent = db.query(Duel).filter(mine, Duel.status == FINISHED).order_by(Duel.id.desc()).limit(5).all()

    def view(d: Duel) -> dict:
        a, b = (d.challenger_xp, d.opponent_xp) if d.status == FINISHED else scores(db, d)
        i_am_challenger = d.challenger_id == user.id
        other = db.get(User, d.opponent_id if i_am_challenger else d.challenger_id)
        return {
            "id": d.id,
            "status": d.status,
            "week_start": d.week_start,
            "ends_at": datetime.combine(d.week_start, datetime.min.time(), tzinfo=DUSHANBE_TZ) + timedelta(days=7),
            "i_challenged": i_am_challenger,
            "opponent_id": other.id if other else 0,
            "opponent_login": other.login if other else "",
            "opponent_avatar_url": url_for_key(other.avatar_key) if other else None,
            "my_xp": a if i_am_challenger else b,
            "their_xp": b if i_am_challenger else a,
            "won": None if d.winner_id is None else d.winner_id == user.id,
        }

    return {
        "enabled": get_pass_settings(db).duels_enabled,
        "current": view(current) if current else None,
        "recent": [view(d) for d in recent],
    }


def after_xp(db: Session, user: User) -> None:
    """Called when someone earned XP: tell the opponent once a day if they were just overtaken."""
    try:
        duel = (
            db.query(Duel)
            .filter(
                Duel.status == ACTIVE,
                Duel.week_start == week_start(dushanbe_today()),
                or_(Duel.challenger_id == user.id, Duel.opponent_id == user.id),
            )
            .first()
        )
        if duel is None:
            return
        a, b = scores(db, duel)
        mine, theirs = (a, b) if duel.challenger_id == user.id else (b, a)
        if mine > theirs:
            other = db.get(User, duel.opponent_id if duel.challenger_id == user.id else duel.challenger_id)
            if other:
                _notify(db, other, "overtaken", f"duel-overtaken:{duel.id}:{dushanbe_today().isoformat()}", name=_name(user))
    except Exception:
        logger.exception("duel after_xp failed")


def finish_due(db: Session, today: date | None = None) -> int:
    """Closes duels of past weeks: decides the winner, pays the bonus, tells both."""
    monday = week_start(today or dushanbe_today())
    closed = 0
    for duel in db.query(Duel).filter(Duel.status.in_([PENDING, ACTIVE]), Duel.week_start < monday).all():
        if duel.status == PENDING:
            duel.status = CANCELLED
            continue
        a, b = scores(db, duel)
        duel.challenger_xp, duel.opponent_xp = a, b
        duel.status = FINISHED
        duel.winner_id = duel.challenger_id if a > b else duel.opponent_id if b > a else None
        bonus = get_pass_settings(db).xp_duel_win
        users = {u.id: u for u in db.query(User).filter(User.id.in_([duel.challenger_id, duel.opponent_id]))}
        for me_id, other_id, mine, theirs in (
            (duel.challenger_id, duel.opponent_id, a, b),
            (duel.opponent_id, duel.challenger_id, b, a),
        ):
            me, other = users.get(me_id), users.get(other_id)
            if me is None or other is None:
                continue
            key = f"duel-result:{duel.id}"
            if mine > theirs:
                award_xp(db, me, "duel", f"duel:{duel.id}", bonus)
                _notify(db, me, "won", key, name=_name(other), mine=mine, theirs=theirs, bonus=bonus)
            elif mine < theirs:
                _notify(db, me, "lost", key, name=_name(other), mine=mine, theirs=theirs)
            else:
                _notify(db, me, "draw", key, name=_name(other), mine=mine, theirs=theirs)
        closed += 1
    return closed
