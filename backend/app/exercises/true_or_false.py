"""Правда или ложь: for each of a Lesson's own words, decide whether the
shown translation is real or borrowed from a different, PREVIOUSLY learned
word (never from this same lesson's own words -- confirmed as an always-
required external pool, not a same-lesson fallback). Moved unchanged from
app/routers/lessons.py."""

import random

from sqlalchemy.orm import Session

from app.core.storage import url_for_key
from app.exercises.common import get_learned_pool, lesson_words_pending
from app.models.lesson import Lesson
from app.models.user import User
from app.models.word import Word
from app.priority.distractors import prefer_distractor_words
from app.schemas.exercise import TrueOrFalseItemOut, TrueOrFalseRoundOut

KEY = "true_or_false"


def is_available(db: Session, user: User, dictionary_id: int, lesson_word_ids: list[int], threshold: int) -> bool:
    """Requires at least one PREVIOUSLY learned word (never this lesson's
    own words) to draw wrong-answer candidates from."""
    return len(get_learned_pool(db, user.id, dictionary_id, threshold)) >= 1


def build_round(db: Session, lesson: Lesson, threshold: int) -> TrueOrFalseRoundOut:
    lesson_words = [w for w in lesson_words_pending(db, lesson, threshold) if w.translations]
    learned_pool = get_learned_pool(db, lesson.user_id, lesson.dictionary_id, threshold)

    def primary_text(word: Word) -> str:
        return word.translations[0].text

    def primary_audio(word: Word) -> str | None:
        return url_for_key(word.translations[0].audio_key)

    items: list[TrueOrFalseItemOut] = []
    for word in lesson_words:
        real_text = primary_text(word)
        show_real = random.random() < 0.5

        fake_candidates = []
        if not show_real:
            fake_candidates = [w for w in learned_pool if w.id != word.id and primary_text(w) != real_text]
            if not fake_candidates:
                fake_candidates = [w for w in learned_pool if w.id != word.id]

        if show_real or not fake_candidates:
            shown_text, shown_audio, is_correct = real_text, primary_audio(word), True
        else:
            fake_word = prefer_distractor_words(db, lesson.user_id, fake_candidates)[0]
            shown_text, shown_audio, is_correct = primary_text(fake_word), primary_audio(fake_word), False

        items.append(
            TrueOrFalseItemOut(
                word_id=word.id,
                original=word.word,
                transcription=word.transcription,
                image_url=url_for_key(word.image_key),
                word_audio_url=url_for_key(word.word_audio_key),
                shown_translation=shown_text,
                shown_translation_audio_url=shown_audio,
                is_correct=is_correct,
            )
        )

    return TrueOrFalseRoundOut(dictionary_id=lesson.dictionary_id, available_count=len(lesson_words), items=items)
