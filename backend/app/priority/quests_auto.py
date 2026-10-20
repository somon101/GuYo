"""Personal auto-quests: the backend's own Quests, created for ONE user --
one per exercise, side by side -- when enough of their High/Medium-priority
words turn out to share the same weak exercise -- the same kind of automatic
side effect app/priority/lessons.py's maybe_create_adaptive_lesson already is for
Lesson, just for Quest (see app/models/quest.py's own docstring on how a
personal Quest reuses the exact same table and serving flow as an
admin-authored one).

Two conditions, both required, exactly as agreed with the user:
1. the word's CURRENT Priority role is High or Medium;
2. among words that pass (1), every exercise that at least
   personal_quest_min_words of them are individually weak in -- "weak"
   meaning at least personal_quest_min_attempts attempts in it with an
   error rate of at least personal_quest_weak_error_rate -- becomes a quest
   of its own (that exercise is the quest's one exercise_key).

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
    app/routers/admin_analytics.py) and maybe_create_personal_quests below
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
        .filter(WordAttempt.user_id == user_id, WordAttempt.word_id.in_(word_ids), WordAttempt.source != "check")
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


def _words_in_open_personal_quests(db: Session, user_id: int, dictionary_id: int) -> set[int]:
    """Words pinned in this user's personal quests that still have unfinished
    words -- they are not put into a new quest, which is what stops the same
    quest from being created over and over."""
    quests = db.query(Quest).filter(Quest.owner_user_id == user_id, Quest.enabled.is_(True)).all()
    taken: set[int] = set()
    for quest in quests:
        pinned = [w for (w,) in db.query(QuestWord.word_id).filter(QuestWord.quest_id == quest.id).all()]
        if not pinned:
            continue
        first_word = db.get(Word, pinned[0])
        if first_word is None or first_word.dictionary_id != dictionary_id:
            continue
        done = db.query(UserQuestWordDay).filter(UserQuestWordDay.quest_id == quest.id).count()
        if done < len(pinned):
            taken.update(pinned)
    return taken


def maybe_create_personal_quests(db: Session, user: User, dictionary_id: int) -> list[Quest]:
    """Called by the background preparation (app/priority/background_prep.py).
    One personal quest per exercise that enough High/Medium-priority words are
    weak in -- as many as there are, side by side. A word goes into one quest
    only, and a word already in an unfinished personal quest is left out, so a
    new quest appears only when new weak words have gathered. Empty if the
    user lacks Premium while personal quests are Premium-only.

    Does NOT commit -- runs inside the caller's own transaction."""
    # Deferred imports: app.exercises (and app.quests.rounds, which
    # reaches back into app.priority via app.priority.distractors) both
    # ultimately import THIS package at module load time.
    from app.exercises import EXERCISE_TYPES
    from app.quests.rounds import is_quest_word_feasible

    # Premium-only unless the admin switched that off (PremiumSettings).
    if not automatic_feature_allowed(db, user, FEATURE_PERSONAL_QUESTS):
        return []

    settings = get_priority_settings(db)
    taken = _words_in_open_personal_quests(db, user.id, dictionary_id)
    pool = [(word, score) for word, score in _high_medium_words(db, user.id, dictionary_id) if word.id not in taken]
    if not pool:
        return []

    weak = weak_exercises_by_word(db, user.id, [word.id for word, _ in pool])
    by_exercise: dict[str, list[tuple[Word, float]]] = defaultdict(list)
    for word, score in pool:
        for exercise_key in weak[word.id]:
            by_exercise[exercise_key].append((word, score))

    # The exercise with the most weak words goes first; ties follow the
    # registry's fixed order, so equal runs always give the same quests.
    order = {key: i for i, key in enumerate(EXERCISE_TYPES)}
    exercises = sorted(by_exercise, key=lambda key: (-len(by_exercise[key]), order.get(key, len(order))))

    created: list[Quest] = []
    used: set[int] = set()
    for exercise_key in exercises:
        # Most urgent (highest Priority Score) first, feasibility-checked
        # (e.g. listen_word needs its own recording) and capped.
        candidates = sorted(
            (pair for pair in by_exercise[exercise_key] if pair[0].id not in used), key=lambda pair: -pair[1]
        )
        if len(candidates) < settings.personal_quest_min_words:
            continue
        chosen: list[Word] = []
        for word, _score in candidates:
            if is_quest_word_feasible(db, user, dictionary_id, exercise_key, word):
                chosen.append(word)
            if len(chosen) >= settings.personal_quest_max_words:
                break
        if len(chosen) < settings.personal_quest_min_words:
            continue

        quest = Quest(
            name=f"Персонально: {_EXERCISE_LABELS.get(exercise_key, exercise_key)}",
            word_level_id=None,
            exercise_key=exercise_key,
            reward_points=settings.personal_quest_reward_points,
            daily_target=len(chosen),
            enabled=True,
            owner_user_id=user.id,
        )
        db.add(quest)
        db.flush()
        for word in chosen:
            db.add(QuestWord(quest_id=quest.id, word_id=word.id))
            used.add(word.id)
        log_event(db, user.id, "personal_quest_created", quest_id=quest.id,
                  data={"name": quest.name, "words": len(chosen)})
        created.append(quest)
    return created
