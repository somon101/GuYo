"""Shared, exercise-type-agnostic infrastructure: the global learning
threshold, per-exercise-key points, and the two word pools every Lesson
exercise type draws from (the not-yet-learned pool a new Lesson picks
from, and the already-learned pool "Правда или ложь" borrows wrong
answers from). Moved here unchanged from app/routers/lessons.py so every
exercise type module (see app/exercises/__init__.py) shares ONE copy of
this instead of each re-querying it independently.
"""

from sqlalchemy.orm import Session

from app.models.exercise import ExerciseSettings
from app.models.learning_settings import LearningSettings
from app.models.word import Word
from app.models.word_progress import WordProgress

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
    learned_ids = (
        db.query(WordProgress.word_id)
        .filter(WordProgress.user_id == user_id, WordProgress.score >= threshold)
        .subquery()
    )
    return db.query(Word).filter(Word.dictionary_id == dictionary_id, ~Word.id.in_(learned_ids)).all()


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
    words = db.query(Word).filter(Word.dictionary_id == dictionary_id, Word.id.in_(learned_ids)).all()
    return [w for w in words if w.translations]
