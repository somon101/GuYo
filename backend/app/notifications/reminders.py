"""Automatic reminders, written by the admin in Admin Web (ReminderRule).

- inactivity: after exactly N whole days without opening the app (N=1:
  missed yesterday), at the hour the user usually studies. Someone active
  yesterday but not yet today is the streak warning's case, not this one. "Exactly" matters: someone who has been away
  for 10 days when a 7-day rule is added does not get it late.
- streak_risk: in the evening, to someone whose streak is still alive
  (active yesterday) but who has not opened the app today.
- streak_milestone: the day a streak reaches N -- sent from
  record_activity the moment that day is recorded, not by the sweep.

Everything goes through send_notification with a dedupe key, so the sweep
can run as often as it likes and a restart never sends anything twice.
Days are Asia/Dushanbe calendar days, the same calendar the streak uses.
"""

import logging
import random
from collections import Counter, defaultdict
from datetime import date, timedelta

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.achievements.conditions import streak_days_count
from app.core.dates import DUSHANBE_TZ, dushanbe_today, utc_now
from app.models.achievement import UserActivityDay
from app.models.notification import (
    REMINDER_INACTIVITY,
    REMINDER_STREAK_MILESTONE,
    REMINDER_STREAK_RISK,
    ReminderRule,
    ReminderSettings,
)
from app.models.user import User
from app.models.word_attempt import WordAttempt
from app.notifications.service import send_notification

logger = logging.getLogger(__name__)

SOURCE_INACTIVITY = "reminder_inactivity"
SOURCE_STREAK_RISK = "reminder_streak_risk"
SOURCE_STREAK_MILESTONE = "reminder_streak_milestone"

# How far back "the hour this person usually studies" looks.
USUAL_HOUR_LOOKBACK_DAYS = 30


def get_reminder_settings(db: Session) -> ReminderSettings:
    settings = db.get(ReminderSettings, 1)
    if settings is None:
        settings = ReminderSettings(id=1)
        db.add(settings)
        db.flush()
    return settings


def render(text: str, days: int) -> str:
    return text.replace("{дни+1}", str(days + 1)).replace("{дни}", str(days))


def _enabled_rules(db: Session, kind: str) -> list[ReminderRule]:
    return db.query(ReminderRule).filter(ReminderRule.kind == kind, ReminderRule.enabled.is_(True)).all()


def _send(db: Session, user: User, variants: list[ReminderRule], days: int, source: str, dedupe_key: str):
    rule = random.choice(variants)
    return send_notification(
        db,
        user,
        render(rule.body, days),
        title=render(rule.title, days) if rule.title else None,
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
    return {user_id: counter.most_common(1)[0][0] for user_id, counter in hours.items()}


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


def run_reminders(db: Session) -> int:
    now = utc_now().astimezone(DUSHANBE_TZ)
    settings = get_reminder_settings(db)
    return send_inactivity_reminders(db, now.date(), now.hour, settings) + send_streak_risk_reminders(
        db, now.date(), now.hour, settings
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
