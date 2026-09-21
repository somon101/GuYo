"""Сопоставление: shuffle a Lesson's own word set into two columns for a
tap-to-match drill. Moved unchanged from app/routers/lessons.py."""

from sqlalchemy.orm import Session

from app.models.lesson import Lesson
from app.models.user import User
from app.routers.words import word_to_out
from app.schemas.exercise import ExerciseWordsOut

KEY = "matching"


def is_available(db: Session, user: User, dictionary_id: int, lesson_word_ids: list[int], threshold: int) -> bool:
    return len(lesson_word_ids) >= 2


def build_round(db: Session, lesson: Lesson) -> ExerciseWordsOut:
    words = [lw.word for lw in lesson.words if lw.word.translations]
    return ExerciseWordsOut(
        dictionary_id=lesson.dictionary_id,
        exercise_key=KEY,
        available_count=len(words),
        words=[word_to_out(w) for w in words],
    )
