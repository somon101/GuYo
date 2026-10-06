"""Shared, exercise-type-agnostic infrastructure: the global learning
threshold, per-exercise-key points, and the two word pools every Lesson
exercise type draws from (the not-yet-learned pool a new Lesson picks
from, and the already-learned pool "Правда или ложь" borrows wrong
answers from). Moved here unchanged from app/routers/lessons.py so every
exercise type module (see app/exercises/__init__.py) shares ONE copy of
this instead of each re-querying it independently.
"""

from sqlalchemy.orm import Session, selectinload

from app.models.exercise import ExerciseSettings
from app.models.learning_settings import LearningSettings
from app.models.lesson import Lesson
from app.models.word import Word
from app.models.word_progress import WordProgress
from app.word_levels import level_for_score_in, ordered_enabled_levels, top_level_threshold

DEFAULT_THRESHOLD = 60
# (correct, incorrect) points, only used when an admin hasn't configured a
# given exercise_key's own values yet -- purely illustrative numbers from
# the original spec, not meant to be load-bearing once Admin Web has real
# settings for every exercise_key.
DEFAULT_POINTS: dict[str, tuple[int, int]] = {
    "matching": (20, 10),
    "true_or_false": (10, 5),
    "build_word": (30, 15),
    "speaking_word": (15, 5),
    "listen_word": (15, 5),
}


def get_threshold(db: Session) -> int:
    """The score a word needs to reach before it counts as learned. Once an
    admin has configured the WordLevel ladder (see app/word_levels/), this
    is the top enabled level's min_points -- level 5 "Закреплено" in the
    spec's own example. Falls back to the legacy single LearningSettings
    number until then, so nothing breaks before an admin sets up levels."""
    top = top_level_threshold(db)
    if top is not None:
        return top
    settings = db.get(LearningSettings, 1)
    return settings.threshold_score if settings is not None else DEFAULT_THRESHOLD


def get_exercise_settings_row(db: Session, exercise_key: str) -> ExerciseSettings | None:
    return db.query(ExerciseSettings).filter(ExerciseSettings.exercise_key == exercise_key).first()


def is_exercise_enabled(db: Session, exercise_key: str) -> bool:
    """Null/unset means enabled -- same "unset = working default"
    convention as every other ExerciseSettings field."""
    settings = get_exercise_settings_row(db, exercise_key)
    return settings is None or settings.enabled is not False


def get_points(db: Session, exercise_key: str) -> tuple[int, int]:
    """(correct_points, incorrect_points) -- incorrect_points is always a
    positive "how much to subtract" number, matching how Admin Web presents
    it (e.g. "-10" meaning score decreases by 10)."""
    settings = get_exercise_settings_row(db, exercise_key)
    default_correct, default_incorrect = DEFAULT_POINTS.get(exercise_key, (10, 5))
    correct = settings.correct_points if settings and settings.correct_points is not None else default_correct
    incorrect = settings.incorrect_points if settings and settings.incorrect_points is not None else default_incorrect
    return correct, incorrect


def get_eligible_words(db: Session, user_id: int, dictionary_id: int, threshold: int) -> list[Word]:
    """Every Word in this dictionary NOT already learned (WordProgress.score
    >= threshold) -- the one pool both lesson-creation modes (random and
    manual) draw from, so a word already mastered is never offered again."""
    from app.memory import secured_word_ids

    secured = secured_word_ids(db, user_id, None, threshold)
    return [w for w in db.query(Word).filter(Word.dictionary_id == dictionary_id).all() if w.id not in secured]


def fill_word_progress(db: Session, user_id: int, words_out: list, word_ids: list[int]) -> None:
    """Fills each WordOut's own `score`/`word_level_id`/`word_level_name`
    with THIS user's progress, in place. One query for the scores and one
    for the level ladder no matter how many words -- and the same
    ordered_enabled_levels/level_for_score_in pair every other caller uses,
    so a word's level here can never disagree with the one Quests or
    "Мои слова" would show for the same score."""
    if not word_ids:
        return
    scores = {
        row.word_id: row.score
        for row in db.query(WordProgress)
        .filter(WordProgress.user_id == user_id, WordProgress.word_id.in_(word_ids))
        .all()
    }
    levels = ordered_enabled_levels(db)
    for out in words_out:
        score = scores.get(out.id, 0)
        level = level_for_score_in(levels, score)
        out.score = score
        out.word_level_id = level.id if level else None
        out.word_level_name = level.name if level else None


def lesson_words_pending(db: Session, lesson: Lesson, threshold: int) -> list[Word]:
    """The words every exercise type's build_round draws its round from.

    Once a pass has been started (Lesson.pass_word_ids, set by POST
    /lessons/{id}/pass), that is exactly the set frozen at its start:
    within one pass every word goes through every exercise, even a word
    that crosses its level partway through. The narrowing to "only what's
    still short" happens when the NEXT pass starts, so a "Повторить урок"
    pass never re-tests words already secured.

    A lesson no pass was ever started for (older app versions) keeps the
    old behavior: the words below the threshold right now."""
    if lesson.pass_word_ids is not None:
        frozen = set(lesson.pass_word_ids)
        return [lw.word for lw in lesson.words if lw.word_id in frozen]
    return lesson_words_below_threshold(db, lesson, threshold)


def lesson_words_below_threshold(db: Session, lesson: Lesson, threshold: int) -> list[Word]:
    """This lesson's own words that HAVEN'T yet reached the threshold right
    now -- what a new pass covers. On a lesson's first pass that is every
    word. A word with no WordProgress row at all counts as below threshold
    (score 0), same convention as everywhere else scoring is read."""
    from app.memory import secured_word_ids

    word_ids = [lw.word_id for lw in lesson.words]
    if not word_ids:
        return []
    secured = secured_word_ids(db, lesson.user_id, word_ids, threshold)
    return [lw.word for lw in lesson.words if lw.word_id not in secured]


def get_learned_pool(db: Session, user_id: int, dictionary_id: int, threshold: int) -> list[Word]:
    """The inverse of `get_eligible_words`: words already learned (score >=
    threshold) with a translation to show -- "Правда или ложь"'s ONLY
    source of wrong-answer candidates, deliberately never a lesson's own
    words (see true_or_false.is_available)."""
    learned_ids = (
        db.query(WordProgress.word_id)
        .filter(WordProgress.user_id == user_id, WordProgress.score >= threshold)
        .subquery()
    )
    words = (
        db.query(Word)
        .options(selectinload(Word.translations))
        .filter(Word.dictionary_id == dictionary_id, Word.id.in_(learned_ids))
        .all()
    )
    return [w for w in words if w.translations]
