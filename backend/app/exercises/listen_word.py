"""Услышь слово: automatically play a Lesson word's own recording, then
offer it among a shuffled multiple-choice drawn from the user's own
PREVIOUSLY learned words (never this same lesson's own words -- same
always-required-external-pool rule as app/exercises/true_or_false.py, and
the same Priority-aware preference via app.priority.distractors --
distractor words are ALWAYS drawn through Priority, everywhere, no
exceptions). Correctness is decided purely by word_id (never by comparing
button text), same "backend decides the round, client compares a tap"
principle as every other exercise. Only words with their OWN recording can
ever be the thing being listened to -- there's nothing to listen to
otherwise.
"""

import random

from sqlalchemy.orm import Session

from app.core.storage import url_for_key
from app.exercises.common import get_exercise_settings_row, get_learned_pool, lesson_words_pending
from app.models.lesson import Lesson
from app.models.user import User
from app.models.word import Word
from app.priority.distractors import prefer_distractor_words
from app.schemas.lesson import ListenWordItemOut, ListenWordOptionOut, ListenWordRoundOut

KEY = "listen_word"
DEFAULT_OPTION_COUNT = 4


def get_option_count(db: Session) -> int:
    settings = get_exercise_settings_row(db, KEY)
    if settings and settings.option_count is not None:
        return settings.option_count
    return DEFAULT_OPTION_COUNT


def is_available(db: Session, user: User, dictionary_id: int, lesson_word_ids: list[int], threshold: int) -> bool:
    """Requires at least one lesson word with its own recording (something
    to play) and at least one PREVIOUSLY learned word (never this lesson's
    own words) to draw wrong-answer candidates from -- mirrors Правда или
    ложь's own external-pool requirement exactly."""
    if not get_learned_pool(db, user.id, dictionary_id, threshold):
        return False
    words = db.query(Word).filter(Word.id.in_(lesson_word_ids)).all()
    return any(w.word_audio_key for w in words)


def build_round(db: Session, lesson: Lesson, threshold: int) -> ListenWordRoundOut:
    playable_words = [w for w in lesson_words_pending(db, lesson, threshold) if w.word_audio_key]
    learned_pool = get_learned_pool(db, lesson.user_id, lesson.dictionary_id, threshold)
    option_count = get_option_count(db)

    items: list[ListenWordItemOut] = []
    for word in playable_words:
        candidates = [w for w in learned_pool if w.id != word.id]
        wrong_count = min(option_count - 1, len(candidates))
        others = prefer_distractor_words(db, lesson.user_id, candidates)[:wrong_count]
        options = [ListenWordOptionOut(word_id=word.id, word=word.word)] + [
            ListenWordOptionOut(word_id=w.id, word=w.word) for w in others
        ]
        random.shuffle(options)
        items.append(
            ListenWordItemOut(word_id=word.id, word_audio_url=url_for_key(word.word_audio_key), options=options)
        )

    return ListenWordRoundOut(dictionary_id=lesson.dictionary_id, available_count=len(playable_words), items=items)
