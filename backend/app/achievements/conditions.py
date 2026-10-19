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
from app.models.lesson import Lesson
from app.models.achievement import UserActivityDay
from app.models.user import User
from app.models.word_progress import WordProgress


def phrases_opened_count(db: Session, user: User) -> int:
    """How many phrases this user has actually OPENED (tapped open in "Мои
    фразы"), across every dictionary -- counts UserPhraseOpen rows (see
    app/models/phrase.py), recorded once per phrase when the user opens it.
    Deliberately NOT "how many phrases became available because their words
    are learned": that needs no action, so it never earned this achievement."""
    from app.models.phrase import UserPhraseOpen

    return db.query(func.count(UserPhraseOpen.id)).filter(UserPhraseOpen.user_id == user.id).scalar() or 0


def words_learned_count(db: Session, user: User) -> int:
    """How many words this user has learned, across every dictionary --
    reuses the exact same WordProgress.mastered_at.isnot(None) definition
    "Мои слова" and the Lessons system already use (see app/exercises/
    common.py's get_threshold), never a second "learned" definition."""
    return (
        db.query(func.count(WordProgress.id))
        .filter(WordProgress.user_id == user.id, WordProgress.mastered_at.isnot(None))
        .scalar()
        or 0
    )


def lessons_completed_count(db: Session, user: User) -> int:
    """How many Lessons this user has actually PLAYED to the end, across
    every dictionary -- counts Lesson.completed_by_pass, set only when the
    user finished the lesson's pass (see app/routers/lessons.py's
    finish_lesson_pass). Deliberately NOT Lesson.is_completed, which also
    flips the moment every word happens to be at threshold (e.g. words
    already known), so a lesson that auto-completed without a real
    playthrough never earns this achievement."""
    return (
        db.query(func.count(Lesson.id))
        .filter(Lesson.user_id == user.id, Lesson.completed_by_pass.is_(True))
        .scalar()
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


def points_earned_count(db: Session, user: User) -> int:
    """The user's CURRENT rating points -- reuses UserRating.total_points,
    the one row app/rating/service.py ever writes points to (see
    app/models/rating.py), never a second points tally. Note: a Season
    reset zeroes total_points, so a new user must reach the threshold
    within a season; an already-granted achievement is never revoked
    (UserAchievement is permanent)."""
    from app.models.rating import UserRating

    row = db.query(UserRating.total_points).filter(UserRating.user_id == user.id).first()
    return row[0] if row else 0


def friends_added_count(db: Session, user: User) -> int:
    """How many friends this user has -- counts this user's own direction
    of Friendship (always mutual, written both ways on add; see
    app/models/friendship.py), never a second definition of "friend"."""
    from app.models.friendship import Friendship

    return db.query(func.count(Friendship.id)).filter(Friendship.user_id == user.id).scalar() or 0


def quest_words_completed_count(db: Session, user: User) -> int:
    """How many words this user has completed in quests, across all days --
    counts UserQuestWordDay rows (the proof a word was used in some quest
    on a day; see app/models/quest.py), never a second quest-progress
    definition."""
    from app.models.quest import UserQuestWordDay

    return db.query(func.count(UserQuestWordDay.id)).filter(UserQuestWordDay.user_id == user.id).scalar() or 0


def mini_phrases_done_count(db: Session, user: User) -> int:
    """How many mini-phrases this user has gone through -- counts
    UserMiniPhraseDone rows (written once per mini-phrase when it was
    worked through in a lesson; see app/mini_phrases/service.py's mark_done)."""
    from app.models.mini_phrase import UserMiniPhraseDone

    return db.query(func.count(UserMiniPhraseDone.id)).filter(UserMiniPhraseDone.user_id == user.id).scalar() or 0


# condition_type -> (db, user) -> current value. The one place a new
# condition_type becomes usable by both the granting service and the
# "current progress" numbers shown in the Profile screen.
CONDITION_TYPES = {
    "phrases_opened": phrases_opened_count,
    "words_learned": words_learned_count,
    "lessons_completed": lessons_completed_count,
    "streak_days": streak_days_count,
    "points_earned": points_earned_count,
    "friends_added": friends_added_count,
    "quest_words_completed": quest_words_completed_count,
    "mini_phrases_done": mini_phrases_done_count,
}

# condition_type -> a human label for Admin Web's picker -- kept alongside
# CONDITION_TYPES rather than merged into it, since Flutter/the granting
# service never need this text, only Admin Web's UI does.
CONDITION_TYPE_LABELS: dict[str, str] = {
    "phrases_opened": "Количество открытых фраз",
    "words_learned": "Количество изученных слов",
    "lessons_completed": "Количество пройденных уроков",
    "streak_days": "Серия дней активности",
    "points_earned": "Набрано очков",
    "friends_added": "Добавлено друзей",
    "quest_words_completed": "Слова, пройденные в квестах",
    "mini_phrases_done": "Пройдено мини-фраз",
}
