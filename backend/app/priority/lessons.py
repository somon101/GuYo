"""Critical priority's one real effect: once 5 words the user has already
started (and hasn't yet learned) are Critical at the same time, freeze
them into a new Lesson automatically -- through the EXACT SAME
construction app.routers.lessons.build_lesson already uses for a
random/manual lesson, just is_adaptive=True and a Priority-chosen word
set instead of the user's own pick.
"""

from sqlalchemy.orm import Session

from app.exercises.common import get_threshold
from app.models.lesson import Lesson, LessonWord
from app.models.user import User
from app.models.word import Word
from app.models.word_progress import WordProgress
from app.priority.calculate import PriorityResult, calculate_priority
from app.priority.settings import priority_role_bands

# How many Critical words trigger an adaptive lesson -- fixed at 5 by the
# spec's own wording ("когда накопилось 5 слов"), not an admin knob (the
# spec lists this as the one concrete number it does treat as final,
# unlike every band/weight around it).
ADAPTIVE_LESSON_BATCH_SIZE = 5


def _pending_word_ids_in_incomplete_adaptive_lessons(db: Session, user_id: int, dictionary_id: int) -> set[int]:
    """Words already frozen into an adaptive lesson that hasn't been
    completed yet -- excluded from the next accumulation count so the
    SAME 5 words can never trigger a second lesson while the first one is
    still being played. Once that lesson completes, its words simply stop
    appearing here; if they are still (or newly) Critical afterwards they
    are free to count again -- "накопление начинается заново"."""
    rows = (
        db.query(LessonWord.word_id)
        .join(Lesson, Lesson.id == LessonWord.lesson_id)
        .filter(
            Lesson.user_id == user_id,
            Lesson.dictionary_id == dictionary_id,
            Lesson.is_adaptive.is_(True),
            Lesson.is_completed.is_(False),
        )
        .all()
    )
    return {word_id for (word_id,) in rows}


def pending_critical_words(db: Session, user_id: int, dictionary_id: int, threshold: int) -> list[tuple[Word, PriorityResult]]:
    """Every word in this dictionary that:
    - the user has actually started (has a WordProgress row -- a word
      nobody has attempted yet is a Lesson's job to introduce, not this
      one's job to "review"),
    - is not yet learned (same eligibility rule app.routers.lessons.
      create_lesson itself enforces -- a Critical word that is ALSO
      already learned cannot go into a Lesson without changing what a
      Lesson is, which this feature must not do),
    - is not already sitting in an incomplete adaptive lesson,
    - and whose CURRENT Priority role is "critical"."""
    critical_band = priority_role_bands(db)["critical"]
    if critical_band is None:
        return []

    already_pending = _pending_word_ids_in_incomplete_adaptive_lessons(db, user_id, dictionary_id)

    candidates = (
        db.query(Word)
        .join(WordProgress, WordProgress.word_id == Word.id)
        .filter(WordProgress.user_id == user_id, Word.dictionary_id == dictionary_id, WordProgress.score < threshold)
        .all()
    )

    result: list[tuple[Word, PriorityResult]] = []
    for word in candidates:
        if word.id in already_pending:
            continue
        priority = calculate_priority(db, user_id, word.id)
        if priority.level is not None and priority.level.id == critical_band.id:
            result.append((word, priority))
    return result


def maybe_create_adaptive_lesson(db: Session, user: User, dictionary_id: int) -> Lesson | None:
    """Called right after a real attempt is recorded (see
    app.word_attempts.service's call sites in lessons.py/quests.py). None
    if nothing should happen -- no active lesson slot is required (an
    adaptive lesson obeys the exact same "at most one incomplete lesson
    per (user, dictionary)" rule every other lesson does), or fewer than
    ADAPTIVE_LESSON_BATCH_SIZE Critical words currently qualify.

    Does NOT commit -- runs inside the caller's own transaction, same
    contract as every other post-attempt side effect (achievements,
    rating)."""
    # Local imports: app.routers.lessons already imports from app.priority
    # (submit_answer calls maybe_create_adaptive_lesson), so importing it
    # back at module load time would be a cycle -- these are only needed
    # once this function actually runs.
    from app.models.dictionary import Dictionary
    from app.routers.lessons import _get_active_lesson, build_lesson

    if _get_active_lesson(db, user.id, dictionary_id) is not None:
        return None

    threshold = get_threshold(db)
    candidates = pending_critical_words(db, user.id, dictionary_id, threshold)
    if len(candidates) < ADAPTIVE_LESSON_BATCH_SIZE:
        return None

    # Most urgent first -- if more than 5 qualify at once, the batch takes
    # the highest Priority Scores among them.
    candidates.sort(key=lambda pair: -pair[1].score)
    word_ids = [word.id for word, _ in candidates[:ADAPTIVE_LESSON_BATCH_SIZE]]

    dictionary = db.get(Dictionary, dictionary_id)
    return build_lesson(db, user, dictionary, word_ids, threshold, is_adaptive=True)
