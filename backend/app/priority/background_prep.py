"""Quiet background preparation.

Answers no longer build auto lessons/quests on the spot (the learner saw new
lessons pop up mid-session). They only mark (user, dictionary) as pending via
`mark_for_prep`. The scheduler (app/rating/scheduler.py) calls
`run_prep_once` every few minutes: once the learner has been away for
`prep_delay_minutes`, the SAME builders as before run -- maybe_create_
adaptive_lesson / maybe_create_personal_quest, so still at most one active
lesson -- and a push says what was prepared. The same sweep sends at most one
«Повтори слово» push a day when enough words are due. Nothing is prepared or
sent during quiet hours (23:00–08:00 Dushanbe): it simply waits for morning.
"""

import logging
from datetime import timedelta

from sqlalchemy.orm import Session

from app.core.dates import DUSHANBE_TZ, dushanbe_today, utc_now
from app.models.notification import UserPrepState
from app.models.user import User

logger = logging.getLogger(__name__)

SOURCE_PREP_READY = "prep_ready"
SOURCE_REVIEW_DUE = "review_due"
QUIET_FROM_HOUR = 23
QUIET_TO_HOUR = 8

_TEXTS = {
    "lesson": {
        "ru": ("Урок для закрепления готов", "Мы подготовили урок на {words} слов, которые стоит закрепить."),
        "tg": ("Дарси мустаҳкамкунӣ омода аст", "Мо барои {words} калимае, ки бояд мустаҳкам шаванд, дарс омода кардем."),
        "uz": ("Mustahkamlash darsi tayyor", "Mustahkamlash kerak boʻlgan {words} ta soʻz uchun dars tayyorladik."),
        "en": ("Your review lesson is ready", "We have put together a lesson with the {words} words worth reinforcing."),
    },
    "quest": {
        "ru": ("Новый квест готов", "Мы подготовили для тебя персональный квест."),
        "tg": ("Квести нав омода аст", "Мо барои ту квести шахсӣ омода кардем."),
        "uz": ("Yangi kvest tayyor", "Siz uchun shaxsiy kvest tayyorladik."),
        "en": ("A new quest is ready", "We have prepared a personal quest for you."),
    },
    "review": {
        "ru": ("Пора повторить слова", "{words} слов начинают забываться — повтори их за пару минут."),
        "tg": ("Вақти такрори калимаҳо", "{words} калима фаромӯш шуда истодаанд — онҳоро дар чанд дақиқа такрор кун."),
        "uz": ("Soʻzlarni takrorlash vaqti", "{words} ta soʻz unutilyapti — ularni bir necha daqiqada takrorlang."),
        "en": ("Time to review your words", "{words} words are starting to fade — review them in a couple of minutes."),
    },
}


def _text(kind: str, user: User, words: int) -> tuple[str, str]:
    lang = user.ui_language if user.ui_language in ("ru", "tg", "uz", "en") else "ru"
    title, body = _TEXTS[kind][lang]
    return title, body.replace("{words}", str(words))


def mark_for_prep(db: Session, user: User, dictionary_id: int) -> None:
    """Called where the auto builders used to run (after a real answer).
    Does not commit -- part of the caller's transaction."""
    state = (
        db.query(UserPrepState)
        .filter(UserPrepState.user_id == user.id, UserPrepState.dictionary_id == dictionary_id)
        .first()
    )
    if state is None:
        db.add(UserPrepState(user_id=user.id, dictionary_id=dictionary_id, last_activity_at=utc_now(), pending=True))
    else:
        state.last_activity_at = utc_now()
        state.pending = True


def _quiet_now() -> bool:
    hour = utc_now().astimezone(DUSHANBE_TZ).hour
    return hour >= QUIET_FROM_HOUR or hour < QUIET_TO_HOUR


def run_prep(db: Session) -> int:
    """One sweep; returns how many pushes were queued. Does not commit."""
    from app.notifications.reminders import get_reminder_settings
    from app.notifications.service import send_notification
    from app.priority import maybe_create_adaptive_lesson, maybe_create_personal_quest
    from app.routers.practice import review_due_word_ids

    settings = get_reminder_settings(db)
    if not settings.prep_enabled or _quiet_now():
        return 0
    cutoff = utc_now() - timedelta(minutes=settings.prep_delay_minutes)
    today = dushanbe_today()
    sent = 0
    states = (
        db.query(UserPrepState)
        .filter(UserPrepState.last_activity_at <= cutoff)
        .filter((UserPrepState.pending.is_(True)) | (UserPrepState.review_notified_on.is_(None)) | (UserPrepState.review_notified_on < today))
        .limit(500)
        .all()
    )
    for state in states:
        user = db.get(User, state.user_id)
        if user is None:
            continue
        # Still studying in another language? Wait until fully away.
        busier = (
            db.query(UserPrepState.id)
            .filter(UserPrepState.user_id == user.id, UserPrepState.last_activity_at > cutoff)
            .first()
        )
        if busier is not None:
            continue
        try:
            with db.begin_nested():
                if state.pending:
                    state.pending = False
                    lesson = maybe_create_adaptive_lesson(db, user, state.dictionary_id)
                    quest = maybe_create_personal_quest(db, user, state.dictionary_id)
                    if lesson is not None:
                        title, body = _text("lesson", user, len(lesson.words))
                        send_notification(db, user, body, title=title, source=SOURCE_PREP_READY, dedupe_key=f"prep:lesson:{lesson.id}")
                        sent += 1
                    elif quest is not None:
                        title, body = _text("quest", user, 0)
                        send_notification(db, user, body, title=title, source=SOURCE_PREP_READY, dedupe_key=f"prep:quest:{quest.id}")
                        sent += 1
                if state.review_notified_on is None or state.review_notified_on < today:
                    due = review_due_word_ids(db, user.id, state.dictionary_id)
                    if len(due) >= settings.review_push_min_words:
                        state.review_notified_on = today
                        title, body = _text("review", user, len(due))
                        send_notification(
                            db, user, body, title=title, source=SOURCE_REVIEW_DUE,
                            dedupe_key=f"review:{state.dictionary_id}:{today.isoformat()}",
                        )
                        sent += 1
        except Exception:
            logger.exception("background prep failed for user %s", state.user_id)
    return sent


def run_prep_once() -> None:
    """One sweep in its own session; never raises (see app/rating/scheduler.py)."""
    from app.database import SessionLocal

    db = SessionLocal()
    try:
        sent = run_prep(db)
        db.commit()
        if sent:
            logger.info("background prep: %s pushes", sent)
    except Exception:
        logger.exception("background prep sweep failed")
        db.rollback()
    finally:
        db.close()
