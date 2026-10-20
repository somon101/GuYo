"""Season-pass nudges, sent by the reminders sweep (app/notifications/reminders.py):

- reward waiting: a level reward or a weekly task is ready to take (at most
  once every 3 days per person);
- season ending: 3 days or less left and the person has earned XP (once per season);
- team goal close: the team is at 80% of a goal (once per goal, to every member).

All go through send_notification with a dedupe key, so the sweep can run as
often as it likes. Only inside the day window (the reminder default hour to 22:00
Dushanbe), so nobody is woken. Switched off by PassSettings.reminders_enabled."""

import logging
from datetime import timedelta

from sqlalchemy.orm import Session

from app.core.dates import utc_now
from app.models.rating import SEASON_ACTIVE, Season
from app.models.season_pass import PassXpEvent
from app.models.user import User
from app.notifications.service import send_notification
from app.seasonpass import service, teams

logger = logging.getLogger(__name__)

SOURCE = "pass_reminder"
LAST_HOUR = 22
REWARD_EVERY_DAYS = 3
SEASON_END_DAYS = 3
TEAM_NEAR = 0.8

_TEXTS = {
    "reward": {
        "ru": ("Награда ждёт вас", "В пропуске сезона есть награда, которую можно забрать"),
        "tg": ("Мукофот интизор аст", "Дар роҳхати мавсим мукофоте ҳаст, ки онро гирифтан мумкин аст"),
        "uz": ("Mukofot sizni kutmoqda", "Mavsum yo'lida olish mumkin bo'lgan mukofot bor"),
        "en": ("A reward is waiting", "There is a reward in the season pass you can claim"),
    },
    "ending": {
        "ru": ("Сезон скоро закончится", "До конца сезона {days} дн. Успейте набрать XP и забрать награды"),
        "tg": ("Мавсим ба охир мерасад", "То охири мавсим {days} рӯз монд. XP ҷамъ кунед ва мукофот гиред"),
        "uz": ("Mavsum tez orada tugaydi", "Mavsum tugashiga {days} kun qoldi. XP to'plang va mukofotlarni oling"),
        "en": ("The season is ending soon", "{days} day(s) left. Earn XP and claim your rewards in time"),
    },
    "near": {
        "ru": ("Цель команды почти выполнена", "Команда «{team}» уже близко к цели. Ещё немного вместе!"),
        "tg": ("Ҳадафи даста қариб иҷро шуд", "Дастаи «{team}» ба ҳадаф наздик аст. Каме боқӣ монд!"),
        "uz": ("Jamoa maqsadi deyarli bajarildi", "«{team}» jamoasi maqsadga yaqin. Bir oz qoldi!"),
        "en": ("Your team's goal is almost done", "Team “{team}” is close to its goal. Just a little more together!"),
    },
}


def _text(kind: str, user: User, **fields) -> tuple[str, str]:
    lang = user.ui_language if user.ui_language in ("ru", "tg", "uz", "en") else "ru"
    title, body = _TEXTS[kind][lang]
    return title, body.format(**fields)


def _send(db: Session, user: User, kind: str, key: str, **fields) -> int:
    title, body = _text(kind, user, **fields)
    return 1 if send_notification(db, user, body, title=title, source=SOURCE, dedupe_key=key) else 0


def _reward_waiting(state: dict) -> bool:
    for lv in state["levels"]:
        for lane in (lv["free"], lv["premium"]):
            if lane and lane["claimable"]:
                return True
    return any(t["claimable"] for t in state["week"]["tasks"])


def _team_near(db: Session, user: User, season: Season) -> tuple[str, str] | None:
    """(team name, goal ref) of a goal the person's team is at 80%..99% of."""
    member = teams.membership(db, user)
    if member is None:
        return None
    team = db.get(teams.Team, member.team_id)
    members = teams.members_of(db, team)
    definition = service.season_pass(db, season).definition
    monday, start, end = service.week_bounds(utc_now(), season)
    goals = [(g, start, end, f"week:{monday.isoformat()}:{g['id']}") for g in definition.get("team_goals") or []]
    sg = definition.get("team_season_goal")
    if sg:
        goals.append((sg, season.starts_at, season.ends_at, f"season:{sg['id']}"))
    for g, s, e, ref in goals:
        target = g["target_per_member"] * max(2, len(members))
        done = sum(teams._counts(db, team, season, g["metric"], s, e).values())
        if TEAM_NEAR * target <= done < target:
            return team.name, f"{team.id}:{ref}"
    return None


def send_pass_reminders(db: Session, hour: int, default_hour: int) -> int:
    if not (default_hour <= hour < LAST_HOUR):
        return 0
    if not service.get_pass_settings(db).reminders_enabled:
        return 0
    season = db.query(Season).filter(Season.status == SEASON_ACTIVE).first()
    if season is None:
        return 0
    now = utc_now()
    days_left = (season.ends_at - now).days + 1
    with_xp = {r[0] for r in db.query(PassXpEvent.user_id).filter(PassXpEvent.season_id == season.id).distinct()}
    sent = 0
    for user in db.query(User).filter(User.id.in_(with_xp), User.deleted_at.is_(None)).all():
        try:
            if 0 < days_left <= SEASON_END_DAYS:
                sent += _send(db, user, "ending", f"ending:{season.id}", days=days_left)
            near = _team_near(db, user, season)
            if near:
                sent += _send(db, user, "near", f"near:{near[1]}:{user.id}", team=near[0])
            if _reward_waiting(service.user_state(db, user)):
                window = now.toordinal() // REWARD_EVERY_DAYS
                sent += _send(db, user, "reward", f"reward:{season.id}:{window}")
        except Exception:
            logger.exception("pass reminder failed for user %s", user.id)
    return sent
