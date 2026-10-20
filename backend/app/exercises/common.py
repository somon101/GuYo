"""Shared, exercise-type-agnostic infrastructure: per-exercise settings and
the two word pools every Lesson exercise type draws from (the not-yet-learned
pool a new Lesson picks from, and the already-learned pool "Правда или ложь"
borrows wrong answers from). "Learned" is WordProgress.mastered_at -- see
app/learning/mastery.py.
"""

from sqlalchemy.orm import Session, selectinload

from app.models.exercise import ExerciseSettings
from app.models.lesson import Lesson
from app.models.word import Word
from app.models.word_progress import WordProgress
from app.core.content_language import only_translated


def get_exercise_settings_row(db: Session, exercise_key: str) -> ExerciseSettings | None:
    return db.query(ExerciseSettings).filter(ExerciseSettings.exercise_key == exercise_key).first()


def is_exercise_enabled(db: Session, exercise_key: str) -> bool:
    """Null/unset means enabled -- same "unset = working default"
    convention as every other ExerciseSettings field."""
    settings = get_exercise_settings_row(db, exercise_key)
    return settings is None or settings.enabled is not False


def get_eligible_words(db: Session, user_id: int, dictionary_id: int) -> list[Word]:
    """Every Word in this dictionary NOT already learned -- the one pool both lesson-creation modes (random and
    manual) draw from, so a word already mastered is never offered again."""
    from app.memory import secured_word_ids

    secured = secured_word_ids(db, user_id, None)
    words = [w for w in db.query(Word).filter(Word.dictionary_id == dictionary_id).all() if w.id not in secured]
    return only_translated(words)


def fill_word_progress(db: Session, user_id: int, words_out: list, word_ids: list[int]) -> None:
    """Fills each WordOut's own `score` (100 = learned, 0 = not: kept for
    installed apps) and memory level with THIS user's progress, in place."""
    if not word_ids:
        return
    from app.learning.mastery import learned_ids
    from app.word_levels import memory_levels_for

    levels = memory_levels_for(db, user_id, word_ids)
    learned = learned_ids(db, user_id, word_ids)
    for out in words_out:
        level = levels.get(out.id)
        out.score = 100 if out.id in learned else 0
        out.word_level_id = level.id if level else None
        out.word_level_name = level.name if level else None


def lesson_words_pending(db: Session, lesson: Lesson) -> list[Word]:
    """The words every exercise type's build_round draws its round from.

    Once a pass has been started (Lesson.pass_word_ids, set by POST
    /lessons/{id}/pass), that is exactly the set frozen at its start:
    within one pass every word goes through every exercise, even a word
    that crosses its level partway through. The narrowing to "only what's
    still short" happens when the NEXT pass starts, so a "Повторить урок"
    pass never re-tests words already secured.

    A lesson no pass was ever started for (older app versions) keeps the
    old behavior: the words not learned yet."""
    if lesson.pass_word_ids is not None:
        frozen = set(lesson.pass_word_ids)
        words = [lw.word for lw in lesson.words if lw.word_id in frozen]
    else:
        words = lesson_words_not_learned(db, lesson)
    # A round asked for only some words (the app re-asking a word answered
    # wrong earlier in the pass): see app/routers/lessons.py's `word_ids`.
    only = getattr(lesson, "only_word_ids", None)
    if only is not None:
        words = [w for w in words if w.id in only]
    return words


def lesson_words_not_learned(db: Session, lesson: Lesson) -> list[Word]:
    """This lesson's own words not learned yet -- what a new pass covers.
    On a lesson's first pass that is every word."""
    from app.memory import secured_word_ids

    word_ids = [lw.word_id for lw in lesson.words]
    if not word_ids:
        return []
    secured = secured_word_ids(db, lesson.user_id, word_ids)
    return [lw.word for lw in lesson.words if lw.word_id not in secured]


def get_learned_pool(db: Session, user_id: int, dictionary_id: int) -> list[Word]:
    """The inverse of `get_eligible_words`: words already learned with a translation to show -- "Правда или ложь"'s ONLY
    source of wrong-answer candidates, deliberately never a lesson's own
    words (see true_or_false.is_available)."""
    learned_ids = (
        db.query(WordProgress.word_id)
        .filter(WordProgress.user_id == user_id, WordProgress.mastered_at.isnot(None))
        .subquery()
    )
    words = (
        db.query(Word)
        .options(selectinload(Word.translations))
        .filter(Word.dictionary_id == dictionary_id, Word.id.in_(learned_ids))
        .all()
    )
    return [w for w in only_translated(words) if w.translations]
