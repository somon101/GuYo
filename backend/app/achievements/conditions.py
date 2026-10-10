"""One function per condition_type, each computing a user's CURRENT numeric
value for that measure. Registering a future condition_type (exercises
done, points earned, ...) is one new function here plus one new entry in
CONDITION_TYPES -- nothing in app/routers/admin_achievements.py, the
Achievement model, or the granting service needs to change.
"""

from datetime import timedelta

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.dates import dushanbe_today
from app.models.dictionary import Dictionary
from app.models.lesson import Lesson
from app.models.phrase import Phrase
from app.models.achievement import UserActivityDay
from app.models.user import User
from app.models.word_progress import WordProgress


def phrases_opened_count(db: Session, user: User) -> int:
    """How many phrases (across every dictionary, not just the one the
    user currently has selected) are available to this user right now --
    reuses the EXACT same per-dictionary availability logic "Мои фразы"
    and Admin Web's "Аналитика пользователей" already use (see
    app/routers/phrases.py's _get_learned_word_tokens/_phrase_is_available)
    rather than a second definition of "opened phrase"."""
    from app.routers.phrases import _get_learned_word_tokens, _phrase_is_available

    dictionary_ids = {row[0] for row in db.query(Phrase.dictionary_id).distinct().all()}
    total = 0
    for dictionary_id in dictionary_ids:
        dictionary = db.get(Dictionary, dictionary_id)
        if dictionary is None:
            continue
        learned_tokens = _get_learned_word_tokens(db, user.id, dictionary)
        phrases = db.query(Phrase).filter(Phrase.dictionary_id == dictionary_id).all()
        total += sum(1 for p in phrases if _phrase_is_available(p, learned_tokens))
    return total


def words_learned_count(db: Session, user: User) -> int:
    """How many words this user has learned, across every dictionary --
    reuses the exact same WordProgress.score >= threshold definition
    "Мои слова" and the Lessons system already use (see app/exercises/
    common.py's get_threshold), never a second "learned" definition."""
    from app.exercises.common import get_threshold

    threshold = get_threshold(db)
    return (
        db.query(func.count(WordProgress.id))
        .filter(WordProgress.user_id == user.id, WordProgress.score >= threshold)
        .scalar()
        or 0
    )


def lessons_completed_count(db: Session, user: User) -> int:
    """How many Lessons this user has fully completed, across every
    dictionary -- reuses Lesson.is_completed exactly as the "Уроки" chain
    screen and lesson-completion logic already set it (see app/routers/
    lessons.py's _check_and_apply_lesson_completion), never a second
    "is this lesson done" check."""
    return (
        db.query(func.count(Lesson.id)).filter(Lesson.user_id == user.id, Lesson.is_completed.is_(True)).scalar()
        or 0
    )


def streak_with_freezes(db: Session, user: User) -> tuple[int, list]:
    """The user's CURRENT streak and the days a "freeze" covered.

    Counted backward from today (or from yesterday while today has no
    activity yet -- the day isn't over). A day without activity doesn't
    break the streak if it is the only such day in its Monday-Sunday week:
    one missed day a week is forgiven automatically, two in a row or two
    in the same week end it. Forgiven days keep the streak alive but don't
    add to it. Computed from UserActivityDay alone, so every screen and
    rule that shows the streak agrees."""
    active = {
        row[0] for row in db.query(UserActivityDay.activity_date).filter(UserActivityDay.user_id == user.id).all()
    }
    if not active:
        return 0, []
    today = dushanbe_today()
    day = today if today in active else today - timedelta(days=1)
    earliest = min(active)
    streak = 0
    frozen: list = []
    used_weeks: set = set()
    pending = None  # a missed day, forgiven only if activity lies before it
    while day >= earliest:
        if day in active:
            if pending is not None:
                frozen.append(pending)
                pending = None
            streak += 1
        else:
            week = day.isocalendar()[:2]
            if pending is not None or week in used_weeks:
                break  # two missed days in a row, or a second in one week
            used_weeks.add(week)
            pending = day
        day -= timedelta(days=1)
    return streak, frozen


def streak_days_count(db: Session, user: User) -> int:
    """The current streak in days -- see streak_with_freezes."""
    return streak_with_freezes(db, user)[0]


# condition_type -> (db, user) -> current value. The one place a new
# condition_type becomes usable by both the granting service and the
# "current progress" numbers shown in the Profile screen.
CONDITION_TYPES = {
    "phrases_opened": phrases_opened_count,
    "words_learned": words_learned_count,
    "lessons_completed": lessons_completed_count,
    "streak_days": streak_days_count,
}

# condition_type -> a human label for Admin Web's picker -- kept alongside
# CONDITION_TYPES rather than merged into it, since Flutter/the granting
# service never need this text, only Admin Web's UI does.
CONDITION_TYPE_LABELS: dict[str, str] = {
    "phrases_opened": "Количество открытых фраз",
    "words_learned": "Количество изученных слов",
    "lessons_completed": "Количество пройденных уроков",
    "streak_days": "Серия дней активности",
}
