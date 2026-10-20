"""Automatic reminders, written by the admin in Admin Web (ReminderRule).

- inactivity: after exactly N whole days without opening the app (N=1:
  missed yesterday), at the hour the user usually studies. Someone active
  yesterday but not yet today is the streak warning's case, not this one. "Exactly" matters: someone who has been away
  for 10 days when a 7-day rule is added does not get it late.
- streak_risk: in the evening, to someone whose streak is still alive
  (active yesterday) but who has not opened the app today.
- streak_milestone: the day a streak reaches N -- sent from
  record_activity the moment that day is recorded, not by the sweep.
- study_time: at each time the user picked to study (UserStudyTime).
- study_followup: ReminderSettings.study_followup_minutes after the day's
  last study time, if the user has answered nothing since that time.
  Never sent at night (from QUIET_FROM_MINUTE).

Everything goes through send_notification with a dedupe key, so the sweep
can run as often as it likes and a restart never sends anything twice.
Days are Asia/Dushanbe calendar days, the same calendar the streak uses.
"""

import logging
import random
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.achievements.conditions import streak_days_count
from app.core.dates import DUSHANBE_TZ, dushanbe_today, utc_now
from app.models.achievement import UserActivityDay
from app.models.notification import (
    REMINDER_INACTIVITY,
    REMINDER_STREAK_MILESTONE,
    REMINDER_STREAK_RISK,
    REMINDER_STUDY_FOLLOWUP,
    REMINDER_STUDY_TIME,
    ReminderRule,
    ReminderSettings,
    UserStudyTime,
)
from app.models.user import User
from app.models.word_attempt import WordAttempt
from app.notifications.service import send_notification

logger = logging.getLogger(__name__)

SOURCE_INACTIVITY = "reminder_inactivity"
SOURCE_STREAK_RISK = "reminder_streak_risk"
SOURCE_STREAK_MILESTONE = "reminder_streak_milestone"
SOURCE_STUDY_TIME = "reminder_study_time"
SOURCE_STUDY_FOLLOWUP = "reminder_study_followup"

# A study reminder is only sent within this many minutes of its time, so a
# backend that was down for hours does not fire a pile of stale ones.
STUDY_SEND_WINDOW_MINUTES = 45
# No follow-ups from 23:00 (Dushanbe) on.
QUIET_FROM_MINUTE = 23 * 60

# How far back "the hour this person usually studies" looks.
USUAL_HOUR_LOOKBACK_DAYS = 30


def get_reminder_settings(db: Session) -> ReminderSettings:
    settings = db.get(ReminderSettings, 1)
    if settings is None:
        settings = ReminderSettings(id=1)
        db.add(settings)
        db.flush()
    return settings


def render(text: str, days: int, words: int | None = None) -> str:
    text = text.replace("{дни+1}", str(days + 1)).replace("{дни}", str(days))
    return text if words is None else text.replace("{слов}", str(words))


def due_word_count(db: Session, user: User) -> int:
    """Learned words the person has forgotten enough to repeat right now."""
    from app.memory.service import due_progress_rows
    from app.models.word import Word
    from app.models.word_progress import WordProgress

    dictionary_ids = [
        r[0]
        for r in db.query(Word.dictionary_id)
        .join(WordProgress, WordProgress.word_id == Word.id)
        .filter(WordProgress.user_id == user.id, WordProgress.mastered_at.isnot(None))
        .distinct()
    ]
    return sum(len(due_progress_rows(db, user.id, d)) for d in dictionary_ids)


def _enabled_rules(db: Session, kind: str) -> list[ReminderRule]:
    return db.query(ReminderRule).filter(ReminderRule.kind == kind, ReminderRule.enabled.is_(True)).all()


def _send(db: Session, user: User, variants: list[ReminderRule], days: int, source: str, dedupe_key: str):
    rule = random.choice(variants)
    # "{слов}" = words due for repeating; counted only for texts that use it.
    words = due_word_count(db, user) if "{слов}" in f"{rule.title or ''}{rule.body}" else None
    return send_notification(
        db,
        user,
        render(rule.body, days, words),
        title=render(rule.title, days, words) if rule.title else None,
        source=source,
        dedupe_key=dedupe_key,
    )


def _usual_hours(db: Session, user_ids: list[int]) -> dict[int, int]:
    """user_id -> the Dushanbe hour they answered most often in the last
    USUAL_HOUR_LOOKBACK_DAYS; users with no answers are left out."""
    since = utc_now() - timedelta(days=USUAL_HOUR_LOOKBACK_DAYS)
    rows = (
        db.query(WordAttempt.user_id, WordAttempt.created_at)
        .filter(WordAttempt.user_id.in_(user_ids), WordAttempt.created_at >= since)
        .all()
    )
    hours: dict[int, Counter] = defaultdict(Counter)
    for user_id, created_at in rows:
        hours[user_id][created_at.astimezone(DUSHANBE_TZ).hour] += 1
    usual = {user_id: counter.most_common(1)[0][0] for user_id, counter in hours.items()}
    # A time the user picked themselves beats a guess from their answers.
    chosen = (
        db.query(UserStudyTime.user_id, func.min(UserStudyTime.minute_of_day))
        .filter(UserStudyTime.user_id.in_(user_ids), UserStudyTime.enabled.is_(True))
        .group_by(UserStudyTime.user_id)
        .all()
    )
    for user_id, minute in chosen:
        usual[user_id] = minute // 60
    return usual


def send_inactivity_reminders(db: Session, today: date, hour: int, settings: ReminderSettings) -> int:
    variants_by_days: dict[int, list[ReminderRule]] = defaultdict(list)
    for rule in _enabled_rules(db, REMINDER_INACTIVITY):
        variants_by_days[rule.days].append(rule)
    if not variants_by_days:
        return 0

    days_by_last_active = {today - timedelta(days=n + 1): n for n in variants_by_days}
    last_active = func.max(UserActivityDay.activity_date)
    rows = (
        db.query(UserActivityDay.user_id, last_active)
        .group_by(UserActivityDay.user_id)
        .having(last_active.in_(list(days_by_last_active)))
        .all()
    )
    if not rows:
        return 0

    user_ids = [user_id for user_id, _ in rows]
    usual = _usual_hours(db, user_ids)
    users = {u.id: u for u in db.query(User).filter(User.id.in_(user_ids)).all()}
    sent = 0
    for user_id, last_day in rows:
        if hour < usual.get(user_id, settings.default_hour):
            continue
        days = days_by_last_active[last_day]
        if _send(db, users[user_id], variants_by_days[days], days, SOURCE_INACTIVITY, f"{days}:{last_day.isoformat()}"):
            sent += 1
    return sent


def send_streak_risk_reminders(db: Session, today: date, hour: int, settings: ReminderSettings) -> int:
    if hour < settings.streak_risk_hour:
        return 0
    rules = _enabled_rules(db, REMINDER_STREAK_RISK)
    if not rules:
        return 0

    active_today = db.query(UserActivityDay.user_id).filter(UserActivityDay.activity_date == today)
    candidates = (
        db.query(User)
        .join(UserActivityDay, UserActivityDay.user_id == User.id)
        .filter(UserActivityDay.activity_date == today - timedelta(days=1), ~User.id.in_(active_today))
        .all()
    )
    sent = 0
    for user in candidates:
        streak = streak_days_count(db, user)
        reached = [r for r in rules if r.days <= streak]
        if not reached:
            continue
        # Several thresholds can be reached at once (say "from 2 days" and
        # "from 30 days"); the most specific one speaks.
        top = max(r.days for r in reached)
        if _send(db, user, [r for r in reached if r.days == top], streak, SOURCE_STREAK_RISK, today.isoformat()):
            sent += 1
    return sent


def send_study_reminders(db: Session, now: datetime, settings: ReminderSettings) -> int:
    """study_time at each picked time, then one study_followup after the
    day's last picked time. `now` is Dushanbe wall-clock time."""
    time_rules = _enabled_rules(db, REMINDER_STUDY_TIME)
    followup_rules = _enabled_rules(db, REMINDER_STUDY_FOLLOWUP)
    if not time_rules and not followup_rules:
        return 0

    today = now.date()
    now_minute = now.hour * 60 + now.minute
    times_by_user: dict[int, list[int]] = defaultdict(list)
    for user_id, minute in (
        db.query(UserStudyTime.user_id, UserStudyTime.minute_of_day).filter(UserStudyTime.enabled.is_(True)).all()
    ):
        times_by_user[user_id].append(minute)
    if not times_by_user:
        return 0

    def due(minute: int) -> bool:
        return minute <= now_minute < minute + STUDY_SEND_WINDOW_MINUTES

    to_remind: dict[int, int] = {}  # user_id -> study minute
    to_follow_up: dict[int, int] = {}  # user_id -> the day's last study minute
    for user_id, minutes in times_by_user.items():
        if time_rules:
            for minute in minutes:
                if due(minute):
                    to_remind[user_id] = minute
        last = max(minutes)
        followup_at = last + settings.study_followup_minutes
        if followup_rules and followup_at < QUIET_FROM_MINUTE and due(followup_at):
            to_follow_up[user_id] = last
    if not to_remind and not to_follow_up:
        return 0

    user_ids = set(to_remind) | set(to_follow_up)
    users = {u.id: u for u in db.query(User).filter(User.id.in_(user_ids)).all()}
    day_start = datetime.combine(today, datetime.min.time(), tzinfo=DUSHANBE_TZ)
    last_answer = dict(
        db.query(WordAttempt.user_id, func.max(WordAttempt.created_at))
        .filter(WordAttempt.user_id.in_(user_ids), WordAttempt.created_at >= day_start)
        .group_by(WordAttempt.user_id)
        .all()
    )

    sent = 0
    for user_id, minute in to_remind.items():
        if user_id not in users:
            continue
        streak = streak_days_count(db, users[user_id])
        if _send(db, users[user_id], time_rules, streak, SOURCE_STUDY_TIME, f"{today.isoformat()}:{minute}"):
            sent += 1
    for user_id, last in to_follow_up.items():
        if user_id not in users:
            continue
        answered = last_answer.get(user_id)
        if answered is not None and answered >= day_start + timedelta(minutes=last):
            continue  # studied after the reminder: no need to nag
        streak = streak_days_count(db, users[user_id])
        if _send(db, users[user_id], followup_rules, streak, SOURCE_STUDY_FOLLOWUP, today.isoformat()):
            sent += 1
    return sent


def congratulate_streak(db: Session, user: User) -> None:
    """Called by record_activity when a new activity day is recorded."""
    rules = _enabled_rules(db, REMINDER_STREAK_MILESTONE)
    if not rules:
        return
    streak = streak_days_count(db, user)
    variants = [r for r in rules if r.days == streak]
    if variants:
        streak_start = dushanbe_today() - timedelta(days=streak - 1)
        _send(db, user, variants, streak, SOURCE_STREAK_MILESTONE, f"{streak}:{streak_start.isoformat()}")


def send_pass_reminders(db: Session, hour: int, default_hour: int) -> int:
    from app.seasonpass.reminders import send_pass_reminders as send

    return send(db, hour, default_hour)


def send_season_summaries(db: Session) -> int:
    from app.seasonpass.reminders import send_season_summaries as send

    return send(db)


def run_reminders(db: Session) -> int:
    now = utc_now().astimezone(DUSHANBE_TZ)
    settings = get_reminder_settings(db)
    return (
        send_inactivity_reminders(db, now.date(), now.hour, settings)
        + send_streak_risk_reminders(db, now.date(), now.hour, settings)
        + send_study_reminders(db, now, settings)
        + send_pass_reminders(db, now.hour, settings.default_hour)
        + send_season_summaries(db)
    )


def run_reminders_once() -> None:
    """One sweep in its own session; never raises (see app/rating/scheduler.py)."""
    from app.database import SessionLocal

    db = SessionLocal()
    try:
        sent = run_reminders(db)
        db.commit()
        if sent:
            logger.info("sent %s reminders", sent)
    except Exception:
        logger.exception("reminder sweep failed")
        db.rollback()
    finally:
        db.close()
