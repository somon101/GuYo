"""Услышь слово: automatically play a Lesson word's own recording, then
offer it among a shuffled multiple-choice of other Lesson words. Correctness
is decided purely by word_id (never by comparing button text), same "backend
decides the round, client compares a tap" principle as every other
exercise. Only words with their OWN recording can ever be the thing being
listened to -- there's nothing to listen to otherwise -- but a lesson word
with no recording of its own can still appear as a wrong-answer button
label, since that only needs its text.
"""

import random

from sqlalchemy.orm import Session

from app.core.storage import url_for_key
from app.exercises.common import get_exercise_settings_row, lesson_words_pending
from app.models.lesson import Lesson
from app.models.user import User
from app.models.word import Word
from app.schemas.lesson import ListenWordItemOut, ListenWordOptionOut, ListenWordRoundOut

KEY = "listen_word"
DEFAULT_OPTION_COUNT = 4


def get_option_count(db: Session) -> int:
    settings = get_exercise_settings_row(db, KEY)
    if settings and settings.option_count is not None:
        return settings.option_count
    return DEFAULT_OPTION_COUNT


def is_available(db: Session, user: User, dictionary_id: int, lesson_word_ids: list[int], threshold: int) -> bool:
    """Needs at least one lesson word with its own recording (something to
    play) and at least 2 lesson words total (something to offer as a wrong
    option) -- mirrors Сопоставление's own ">=2 words" requirement."""
    if len(lesson_word_ids) < 2:
        return False
    words = db.query(Word).filter(Word.id.in_(lesson_word_ids)).all()
    return any(w.word_audio_key for w in words)


def build_round(db: Session, lesson: Lesson, threshold: int) -> ListenWordRoundOut:
    # The distractor pool stays the lesson's FULL word set (any lesson word
    # makes a fine wrong-answer label, already-learned ones included) --
    # only the words actually being TESTED (playable_words) are narrowed to
    # what's still pending, so a repeat pass only quizzes the words that
    # still need it.
    all_words = [lw.word for lw in lesson.words]
    playable_words = [w for w in lesson_words_pending(db, lesson, threshold) if w.word_audio_key]
    option_count = get_option_count(db)

    items: list[ListenWordItemOut] = []
    for word in playable_words:
        others = [w for w in all_words if w.id != word.id]
        random.shuffle(others)
        wrong_count = min(option_count - 1, len(others))
        options = [ListenWordOptionOut(word_id=word.id, word=word.word)] + [
            ListenWordOptionOut(word_id=w.id, word=w.word) for w in others[:wrong_count]
        ]
        random.shuffle(options)
        items.append(
            ListenWordItemOut(word_id=word.id, word_audio_url=url_for_key(word.word_audio_key), options=options)
        )

    return ListenWordRoundOut(dictionary_id=lesson.dictionary_id, available_count=len(playable_words), items=items)
