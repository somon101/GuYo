"""The Sunday-evening recap: how many words the person learned this week,
compared with last week. Sent once per person per week, only to someone who
studied during it; inside the day window (reminder default hour .. 22:00)."""

from datetime import date, timedelta

from sqlalchemy.orm import Session

from app.models.achievement import UserActivityDay
from app.models.user import User
from app.notifications.service import send_notification
from app.progress.stats import week_numbers, week_start

SOURCE = "weekly_digest"
SUNDAY = 6
LAST_HOUR = 22

_TEXTS = {
    "ru": ("Итоги недели", "На этой неделе вы выучили слов: {words}{delta}. Дней занятий: {days}."),
    "tg": ("Натиҷаи ҳафта", "Дар ин ҳафта шумо калимаҳо омӯхтед: {words}{delta}. Рӯзҳои машғулот: {days}."),
    "uz": ("Hafta natijalari", "Bu hafta o'rganilgan so'zlar: {words}{delta}. Mashg'ulot kunlari: {days}."),
    "en": ("Your week", "This week you learned {words} words{delta}. Days studied: {days}."),
}
_BETTER = {"ru": " (на {n} больше, чем на прошлой)", "tg": " ({n} зиёдтар аз ҳафтаи гузашта)", "uz": " (o'tgan haftadan {n} ta ko'p)", "en": " ({n} more than last week)"}
_WORSE = {"ru": " (на {n} меньше, чем на прошлой)", "tg": " ({n} камтар аз ҳафтаи гузашта)", "uz": " (o'tgan haftadan {n} ta kam)", "en": " ({n} fewer than last week)"}


def message(lang: str, words: int, days: int, previous: int) -> tuple[str, str]:
    lang = lang if lang in _TEXTS else "ru"
    diff = words - previous
    delta = _BETTER[lang].format(n=diff) if diff > 0 else _WORSE[lang].format(n=-diff) if diff < 0 else ""
    title, body = _TEXTS[lang]
    return title, body.format(words=words, delta=delta, days=days)


def send_weekly_digests(db: Session, today: date, hour: int, default_hour: int, enabled: bool) -> int:
    if not enabled or today.weekday() != SUNDAY or not (default_hour <= hour < LAST_HOUR):
        return 0
    monday = week_start(today)
    active = {
        r[0]
        for r in db.query(UserActivityDay.user_id).filter(
            UserActivityDay.activity_date >= monday, UserActivityDay.activity_date <= today
        )
    }
    sent = 0
    for user in db.query(User).filter(User.id.in_(active), User.deleted_at.is_(None)).all():
        now = week_numbers(db, user.id, monday)
        before = week_numbers(db, user.id, monday - timedelta(weeks=1))
        title, body = message(user.ui_language, now["words"], now["active_days"], before["words"])
        if send_notification(db, user, body, title=title, source=SOURCE, dedupe_key=monday.isoformat()):
            sent += 1
    return sent
