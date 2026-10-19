"""When a word becomes learned ("изучено") -- without any points.

A word is learned by a lesson pass that PROVES it:

* it was produced from memory at least once (an exercise where the learner
  builds or says the word: RECALL_EXERCISES) and answered right there, and
* its last answer in the pass is right (a mistake is corrected inside the
  same pass: the app asks the word again at the end until it is right).

A lesson with no "from memory" exercise for the word (none enabled, or the
learner skipped speaking) needs right answers in two different exercises
instead -- one guess is never enough.

Learned is set once and never taken back (WordProgress.mastered_at): the
word stays in "Мои слова" however much it is forgotten later; how well it is
remembered is the memory model's job (app/memory/).
"""

from datetime import datetime

from sqlalchemy.orm import Session

from app.core.dates import utc_now
from app.memory.service import RECALL_EXERCISES
from app.models.word_attempt import WordAttempt
from app.models.word_progress import WordProgress

# Without a "from memory" exercise, right answers in this many different
# exercises prove the word.
FALLBACK_DISTINCT_EXERCISES = 2


def proves_word(attempts: list[WordAttempt], lesson_exercises: int = FALLBACK_DISTINCT_EXERCISES) -> bool:
    """Do these answers (one word, one pass, in order) prove the word?
    `lesson_exercises` -- how many exercises the lesson has: only a lesson
    with a single exercise lets one exercise prove a word."""
    if not attempts or not attempts[-1].is_correct:
        return False
    if any(a.exercise_key in RECALL_EXERCISES for a in attempts):
        return any(a.is_correct and a.exercise_key in RECALL_EXERCISES for a in attempts)
    right = {a.exercise_key for a in attempts if a.is_correct}
    return len(right) >= min(FALLBACK_DISTINCT_EXERCISES, max(1, lesson_exercises))


def learned_ids(db: Session, user_id: int, word_ids=None) -> set[int]:
    """The words this user has learned (all of them when `word_ids` is None)."""
    query = db.query(WordProgress.word_id).filter(
        WordProgress.user_id == user_id, WordProgress.mastered_at.isnot(None)
    )
    if word_ids is not None:
        word_ids = list(word_ids)
        if not word_ids:
            return set()
        query = query.filter(WordProgress.word_id.in_(word_ids))
    return {word_id for (word_id,) in query}


def progress_row(db: Session, user_id: int, word_id: int) -> WordProgress:
    """This pair's progress row, created when the word is first answered (the
    memory model keeps its state there). Does not commit."""
    progress = (
        db.query(WordProgress).filter(WordProgress.user_id == user_id, WordProgress.word_id == word_id).first()
    )
    if progress is None:
        progress = WordProgress(user_id=user_id, word_id=word_id, score=0)
        db.add(progress)
        db.flush()
    return progress


def pass_attempts(db: Session, user_id: int, lesson, word_ids=None) -> dict[int, list[WordAttempt]]:
    """This lesson's answers in its current pass, by word, in order."""
    query = db.query(WordAttempt).filter(WordAttempt.user_id == user_id, WordAttempt.lesson_id == lesson.id)
    if lesson.pass_started_at is not None:
        query = query.filter(WordAttempt.created_at >= lesson.pass_started_at)
    if word_ids is not None:
        query = query.filter(WordAttempt.word_id.in_(list(word_ids)))
    out: dict[int, list[WordAttempt]] = {}
    for a in query.order_by(WordAttempt.created_at, WordAttempt.id):
        out.setdefault(a.word_id, []).append(a)
    return out


def apply_pass(db: Session, user_id: int, lesson, word_ids=None, now: datetime | None = None) -> list[int]:
    """Marks every word of this pass that its answers prove as learned.
    Returns the words that became learned just now. Does not commit."""
    now = now or utc_now()
    from app.models.lesson import LessonExercise

    already = learned_ids(db, user_id, [lw.word_id for lw in lesson.words])
    exercises = db.query(LessonExercise).filter(LessonExercise.lesson_id == lesson.id).count()
    newly = []
    for word_id, attempts in pass_attempts(db, user_id, lesson, word_ids).items():
        if word_id in already or not proves_word(attempts, exercises):
            continue
        progress_row(db, user_id, word_id).mastered_at = now
        newly.append(word_id)
    db.flush()
    return newly
