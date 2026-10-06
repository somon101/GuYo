"""Personal auto-quests: the backend's own Quest, created for ONE user
when enough of their High/Medium-priority words turn out to share the
same weak exercise -- the same kind of automatic side effect
app/priority/lessons.py's maybe_create_adaptive_lesson already is for
Lesson, just for Quest (see app/models/quest.py's own docstring on how a
personal Quest reuses the exact same table and serving flow as an
admin-authored one).

Two conditions, both required, exactly as agreed with the user:
1. the word's CURRENT Priority role is High or Medium;
2. among words that pass (1), pick whichever exercise the MOST of them
   are individually weak in -- "weak" meaning at least
   personal_quest_min_attempts attempts in it with an error rate of at
   least personal_quest_weak_error_rate. That exercise becomes the whole
   quest's one exercise_key.

Every number this module reads (min_attempts, weak_error_rate, min_words,
max_words, reward_points) lives on PrioritySettings -- none of it is
fixed business math, same discipline as the rest of Priority.
"""

from collections import defaultdict

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.analytics.history import log_event
from app.models.quest import Quest, QuestWord, UserQuestWordDay
from app.models.user import User
from app.models.word import Word
from app.models.word_attempt import WordAttempt
from app.models.word_progress import WordProgress
from app.premium import FEATURE_PERSONAL_QUESTS, automatic_feature_allowed
from app.priority.calculate import calculate_priorities
from app.priority.settings import get_priority_settings, priority_role_bands

# Display-only labels for the auto-generated quest's `name` -- never read
# by any gating logic, exercise_key alone decides behavior everywhere.
_EXERCISE_LABELS = {
    "true_or_false": "Правда или ложь",
    "matching": "Сопоставление",
    "build_word": "Собери слово",
    "speaking_word": "Произнеси слово",
    "listen_word": "Услышь слово",
}


def weak_exercises_by_word(db: Session, user_id: int, word_ids: list[int]) -> dict[int, list[str]]:
    """word_id -> every exercise_key that (user, word) pair currently looks
    weak in, from one grouped query. Purely a read over WordAttempt -- the
    SAME rule both Admin Web's «Диагностика слова» (see
    app/routers/admin_analytics.py) and maybe_create_personal_quest below
    use, so a word is never "weak" one way in one place and another way in
    the other."""
    if not word_ids:
        return {}
    settings = get_priority_settings(db)
    rows = (
        db.query(
            WordAttempt.word_id,
            WordAttempt.exercise_key,
            func.count(WordAttempt.id),
            func.count(WordAttempt.id).filter(WordAttempt.is_correct.is_(False)),
        )
        .filter(WordAttempt.user_id == user_id, WordAttempt.word_id.in_(word_ids))
        .group_by(WordAttempt.word_id, WordAttempt.exercise_key)
        .order_by(WordAttempt.word_id, WordAttempt.exercise_key)
        .all()
    )
    weak: dict[int, list[str]] = {word_id: [] for word_id in word_ids}
    for word_id, exercise_key, attempts, errors in rows:
        if attempts >= settings.personal_quest_min_attempts and errors / attempts >= settings.personal_quest_weak_error_rate:
            weak[word_id].append(exercise_key)
    return weak


def weak_exercises_for_word(db: Session, user_id: int, word_id: int) -> list[str]:
    return weak_exercises_by_word(db, user_id, [word_id])[word_id]


def _high_medium_words(db: Session, user_id: int, dictionary_id: int) -> list[tuple[Word, float]]:
    """(word, Priority Score) for every word this user has started (has a
    WordProgress row for) in this dictionary whose CURRENT Priority role
    is High or Medium -- condition 1 of the two required for a personal
    quest."""
    roles = priority_role_bands(db)
    target_ids = {band.id for band in (roles["high"], roles["medium"]) if band is not None}
    if not target_ids:
        return []

    candidates = (
        db.query(Word)
        .join(WordProgress, WordProgress.word_id == Word.id)
        .filter(WordProgress.user_id == user_id, Word.dictionary_id == dictionary_id)
        .all()
    )
    priorities = calculate_priorities(db, user_id, [word.id for word in candidates])
    result = []
    for word in candidates:
        priority = priorities[word.id]
        if priority.level is not None and priority.level.id in target_ids:
            result.append((word, priority.score))
    return result


def _incomplete_personal_quest(db: Session, user_id: int, dictionary_id: int) -> Quest | None:
    """A personal quest of this user's, in this dictionary, that still
    has at least one of its pinned QuestWord rows not yet consumed --
    the guard that stops a second one from being created while the first
    is still in progress (same role as app/priority/lessons.py's
    _pending_word_ids_in_incomplete_adaptive_lessons)."""
    quests = db.query(Quest).filter(Quest.owner_user_id == user_id, Quest.enabled.is_(True)).all()
    for quest in quests:
        pinned = db.query(QuestWord.word_id).filter(QuestWord.quest_id == quest.id).all()
        word_ids = [word_id for (word_id,) in pinned]
        if not word_ids:
            continue
        first_word = db.get(Word, word_ids[0])
        if first_word is None or first_word.dictionary_id != dictionary_id:
            continue
        done = db.query(UserQuestWordDay).filter(UserQuestWordDay.quest_id == quest.id).count()
        if done < len(word_ids):
            return quest
    return None


def maybe_create_personal_quest(db: Session, user: User, dictionary_id: int) -> Quest | None:
    """Called right after a real attempt is recorded (same call sites as
    maybe_create_adaptive_lesson: app.routers.lessons.submit_answer and
    app.routers.quests.submit_quest_answer). None if nothing should
    happen -- an incomplete personal quest already exists for this
    (user, dictionary), no exercise currently has enough High/Medium-
    priority words sharing the same weakness, or the user lacks Premium
    while personal quests are Premium-only.

    Does NOT commit -- runs inside the caller's own transaction, same
    contract as every other post-attempt side effect (achievements,
    rating, the adaptive lesson above)."""
    # Deferred imports: app.exercises (and app.quests.rounds, which
    # reaches back into app.priority via app.priority.distractors) both
    # ultimately import THIS package at module load time -- importing
    # them back here at module level would be the same kind of cycle
    # maybe_create_adaptive_lesson already works around this way.
    from app.exercises import EXERCISE_TYPES
    from app.exercises.common import get_threshold
    from app.quests.rounds import is_quest_word_feasible

    # Premium-only unless the admin switched that off (PremiumSettings).
    if not automatic_feature_allowed(db, user, FEATURE_PERSONAL_QUESTS):
        return None

    if _incomplete_personal_quest(db, user.id, dictionary_id) is not None:
        return None

    settings = get_priority_settings(db)
    pool = _high_medium_words(db, user.id, dictionary_id)
    if not pool:
        return None

    weak = weak_exercises_by_word(db, user.id, [word.id for word, _ in pool])
    by_exercise: dict[str, list[tuple[Word, float]]] = defaultdict(list)
    for word, score in pool:
        for exercise_key in weak[word.id]:
            by_exercise[exercise_key].append((word, score))

    # Most weak words wins; ties broken by the exercise registry's own
    # fixed order, for determinism (never random between equal runs).
    best_exercise: str | None = None
    best_words: list[tuple[Word, float]] = []
    for exercise_key in EXERCISE_TYPES:
        candidates = by_exercise.get(exercise_key, [])
        if len(candidates) > len(best_words):
            best_exercise, best_words = exercise_key, candidates

    if best_exercise is None or len(best_words) < settings.personal_quest_min_words:
        return None

    # Most urgent (highest Priority Score) first, feasibility-checked
    # (e.g. listen_word needs its own recording) and capped.
    best_words.sort(key=lambda pair: -pair[1])
    threshold = get_threshold(db)
    chosen: list[Word] = []
    for word, _score in best_words:
        if is_quest_word_feasible(db, user, dictionary_id, threshold, best_exercise, word):
            chosen.append(word)
        if len(chosen) >= settings.personal_quest_max_words:
            break
    if len(chosen) < settings.personal_quest_min_words:
        return None

    quest = Quest(
        name=f"Персонально: {_EXERCISE_LABELS.get(best_exercise, best_exercise)}",
        word_level_id=None,
        exercise_key=best_exercise,
        reward_points=settings.personal_quest_reward_points,
        daily_target=len(chosen),
        enabled=True,
        owner_user_id=user.id,
    )
    db.add(quest)
    db.flush()
    for word in chosen:
        db.add(QuestWord(quest_id=quest.id, word_id=word.id))
    log_event(db, user.id, "personal_quest_created", quest_id=quest.id,
              data={"name": quest.name, "words": len(chosen)})
    return quest
