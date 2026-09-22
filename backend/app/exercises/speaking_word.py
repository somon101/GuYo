"""Произнеси слово: show a Lesson word's text, the user speaks it, an
on-device speech-to-text engine (see mobile/lib/screens/speaking_word_
screen.dart) turns that into text, and the app compares it to the target
word -- entirely on the client, the exact same "backend decides the round
and points, client does the comparison and reports only {word_id,
is_correct}" principle every other exercise already follows (Сопоставление
compares tapped word_ids, Собери слово compares typed letters, etc.). The
backend never receives audio or recognized text, only the final boolean --
there is no server-side speech processing to wire up here.

`match_threshold` is carried on the round (not fetched separately) so the
comparison rule travels with the data it applies to, same pattern as
BuildWordRoundOut.case_sensitive.
"""

from sqlalchemy.orm import Session

from app.core.storage import url_for_key
from app.exercises.common import get_exercise_settings_row, lesson_words_pending
from app.models.lesson import Lesson
from app.models.user import User
from app.schemas.lesson import SpeakingWordItemOut, SpeakingWordRoundOut

KEY = "speaking_word"
DEFAULT_MATCH_THRESHOLD = 70


def get_match_threshold(db: Session) -> int:
    settings = get_exercise_settings_row(db, KEY)
    if settings and settings.speech_match_threshold is not None:
        return settings.speech_match_threshold
    return DEFAULT_MATCH_THRESHOLD


def is_available(db: Session, user: User, dictionary_id: int, lesson_word_ids: list[int], threshold: int) -> bool:
    """Every Lesson word can be read aloud -- the only real requirement is
    that the lesson has words at all (always true) and the exercise itself
    is enabled (checked centrally, see app/exercises/__init__.py)."""
    return len(lesson_word_ids) >= 1


def build_round(db: Session, lesson: Lesson, threshold: int) -> SpeakingWordRoundOut:
    words = lesson_words_pending(db, lesson, threshold)
    items = [
        SpeakingWordItemOut(
            word_id=w.id,
            word=w.word,
            transcription=w.transcription,
            image_url=url_for_key(w.image_key),
        )
        for w in words
    ]
    return SpeakingWordRoundOut(
        dictionary_id=lesson.dictionary_id,
        available_count=len(items),
        match_threshold=get_match_threshold(db),
        items=items,
    )
