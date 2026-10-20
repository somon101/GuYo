"""Quiet background preparation.

Answers no longer build auto lessons/quests on the spot (the learner saw new
lessons pop up mid-session). They only mark (user, dictionary) as pending via
`mark_for_prep`. The scheduler (app/rating/scheduler.py) calls
`run_prep_once` every few minutes: once the learner has been away for
`prep_delay_minutes`, the SAME builders as before run -- maybe_create_
adaptive_lesson / maybe_create_personal_quests, so still at most one active
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
    "quests": {
        "ru": ("Новые квесты готовы", "Мы подготовили для тебя персональные квесты: {quests}."),
        "tg": ("Квестҳои нав омода аст", "Мо барои ту квестҳои шахсӣ омода кардем: {quests}."),
        "uz": ("Yangi kvestlar tayyor", "Siz uchun shaxsiy kvestlar tayyorladik: {quests} ta."),
        "en": ("New quests are ready", "We have prepared personal quests for you: {quests}."),
    },
    "lesson_quests": {
        "ru": ("Урок и квесты готовы", "Мы подготовили урок на {words} слов и персональные квесты: {quests}."),
        "tg": ("Дарс ва квестҳо омода аст", "Мо барои {words} калима дарс ва квестҳои шахсӣ омода кардем: {quests}."),
        "uz": ("Dars va kvestlar tayyor", "{words} ta soʻz uchun dars va shaxsiy kvestlar tayyorladik: {quests} ta."),
        "en": ("Your lesson and quests are ready", "We prepared a lesson with {words} words and personal quests: {quests}."),
    },
    "review": {
        "ru": ("Пора повторить слова", "{words} слов начинают забываться — повтори их за пару минут."),
        "tg": ("Вақти такрори калимаҳо", "{words} калима фаромӯш шуда истодаанд — онҳоро дар чанд дақиқа такрор кун."),
        "uz": ("Soʻzlarni takrorlash vaqti", "{words} ta soʻz unutilyapti — ularni bir necha daqiqada takrorlang."),
        "en": ("Time to review your words", "{words} words are starting to fade — review them in a couple of minutes."),
    },
}


def _text(kind: str, user: User, words: int, quests: int = 0) -> tuple[str, str]:
    lang = user.ui_language if user.ui_language in ("ru", "tg", "uz", "en") else "ru"
    title, body = _TEXTS[kind][lang]
    return title, body.replace("{words}", str(words)).replace("{quests}", str(quests))


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


def touch_activity(db: Session, user: User, dictionary_id: int) -> None:
    """The user is here (a Practice / «Повторить сегодня» answer): the
    away-time clock restarts, but no auto lesson is asked for. Does not
    commit."""
    state = (
        db.query(UserPrepState)
        .filter(UserPrepState.user_id == user.id, UserPrepState.dictionary_id == dictionary_id)
        .first()
    )
    if state is None:
        db.add(UserPrepState(user_id=user.id, dictionary_id=dictionary_id, last_activity_at=utc_now(), pending=False))
    else:
        state.last_activity_at = utc_now()


def _quiet_now(settings) -> bool:
    """The admin's own quiet window (Admin Web -> Напоминания): no background
    preparation goes out inside it. Reads the settings rather than the old
    hardcoded 23:00-08:00, so the window can be moved or turned off entirely
    (a window from==to means "never quiet")."""
    hour = utc_now().astimezone(DUSHANBE_TZ).hour
    if settings.quiet_from_hour == settings.quiet_to_hour:
        return False
    if settings.quiet_from_hour < settings.quiet_to_hour:
        return settings.quiet_from_hour <= hour < settings.quiet_to_hour
    return hour >= settings.quiet_from_hour or hour < settings.quiet_to_hour


def run_prep(db: Session) -> int:
    """One sweep; returns how many pushes were queued. Does not commit."""
    from app.notifications.reminders import get_reminder_settings
    from app.notifications.service import send_notification
    from app.priority import maybe_create_adaptive_lesson, maybe_create_personal_quests

    settings = get_reminder_settings(db)
    if not settings.prep_enabled or _quiet_now(settings):
        return 0
    cutoff = utc_now() - timedelta(minutes=settings.prep_delay_minutes)
    today = dushanbe_today()
    sent = 0
    from app.models.review_list import STATUS_ACTIVE, ReviewList

    # An active «Повторить сегодня» list nobody has been told about yet.
    unnotified = (
        db.query(ReviewList.id)
        .filter(
            ReviewList.user_id == UserPrepState.user_id,
            ReviewList.dictionary_id == UserPrepState.dictionary_id,
            ReviewList.status == STATUS_ACTIVE,
            ReviewList.notified_at.is_(None),
        )
        .exists()
    )
    states = (
        db.query(UserPrepState)
        .filter(UserPrepState.last_activity_at <= cutoff)
        .filter(
            (UserPrepState.pending.is_(True))
            | (UserPrepState.review_notified_on.is_(None))
            | (UserPrepState.review_notified_on < today)
            | unnotified
        )
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
                    quests = maybe_create_personal_quests(db, user, state.dictionary_id)
                    # One push for everything prepared in this sweep.
                    if lesson is not None and quests:
                        title, body = _text("lesson_quests", user, len(lesson.words), quests=len(quests))
                        key = f"prep:lesson:{lesson.id}"
                    elif lesson is not None:
                        title, body = _text("lesson", user, len(lesson.words))
                        key = f"prep:lesson:{lesson.id}"
                    elif quests:
                        title, body = _text("quest" if len(quests) == 1 else "quests", user, 0, quests=len(quests))
                        key = f"prep:quest:{quests[0].id}"
                    else:
                        title = body = key = None
                    if key is not None:
                        send_notification(db, user, body, title=title, source=SOURCE_PREP_READY, dedupe_key=key)
                        sent += 1
                # «Повторить сегодня»: freeze new lists (once a day here; also
                # whenever the app asks), then one push per active list,
                # once the user has been away long enough (practice answers
                # count as activity too -- see touch_activity).
                from app.memory.review_lists import refresh_lists, remaining_word_ids

                if state.review_notified_on is None or state.review_notified_on < today:
                    state.review_notified_on = today
                    active = refresh_lists(db, user.id, state.dictionary_id)
                else:
                    active = (
                        db.query(ReviewList)
                        .filter(
                            ReviewList.user_id == user.id,
                            ReviewList.dictionary_id == state.dictionary_id,
                            ReviewList.status == STATUS_ACTIVE,
                        )
                        .first()
                    )
                if active is not None and active.notified_at is None:
                    left = remaining_word_ids(db, active)
                    if left:
                        active.notified_at = utc_now()
                        title, body = _text("review", user, len(left))
                        send_notification(
                            db, user, body, title=title, source=SOURCE_REVIEW_DUE,
                            dedupe_key=f"review:list:{active.id}",
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
