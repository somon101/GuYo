"""Собери слово: build one task per Lesson word (its own letters, real
order/multiplicity, plus admin-configured wrong distractor letters from the
dictionary's own alphabet, all shuffled together). `_get_build_word_settings`/
`_build_word_item` are the canonical versions -- app/routers/exercises.py's
own (now-unused-by-the-app) dictionary-scoped endpoint imports them from
here rather than keeping a second copy."""

import random

from sqlalchemy.orm import Session

from app.core.storage import url_for_key
from app.exercises.common import get_exercise_settings_row, lesson_words_pending
from app.models.dictionary import Dictionary
from app.models.lesson import Lesson
from app.models.user import User
from app.models.word import Word
from app.schemas.exercise import BuildWordItemOut, BuildWordRoundOut

KEY = "build_word"
DEFAULT_WRONG_LETTER_COUNT = 3
DEFAULT_MIN_WORD_LENGTH = 3
DEFAULT_CASE_SENSITIVE = False


def get_build_word_settings(db: Session) -> tuple[int, int, bool]:
    """(wrong_letter_count, min_word_length, case_sensitive), each
    independently falling back to its own default when unset -- an admin
    can set word_count without having touched these yet."""
    settings = get_exercise_settings_row(db, KEY)
    wrong_letter_count = (
        settings.wrong_letter_count if settings and settings.wrong_letter_count is not None else DEFAULT_WRONG_LETTER_COUNT
    )
    min_word_length = (
        settings.min_word_length if settings and settings.min_word_length is not None else DEFAULT_MIN_WORD_LENGTH
    )
    case_sensitive = (
        settings.case_sensitive if settings and settings.case_sensitive is not None else DEFAULT_CASE_SENSITIVE
    )
    return wrong_letter_count, min_word_length, case_sensitive


def build_item(word: Word, alphabet: str, wrong_letter_count: int) -> BuildWordItemOut:
    """One "Собери слово" task: the real letters of `word.word`, in their
    real order and multiplicity (so e.g. HELLO's two L's are both present),
    plus up to `wrong_letter_count` distractor letters drawn from the
    dictionary's own alphabet, then everything shuffled together.

    Distractors prefer letters that don't appear in the word at all, so
    they never accidentally inflate a letter's count beyond what the real
    word actually has; if the alphabet can't supply enough distinct ones,
    whatever's available is used instead (never padded with duplicates)."""
    correct_word = word.word
    correct_letters = list(correct_word)
    correct_letters_lower = {c.lower() for c in correct_letters}

    candidates = [c for c in alphabet if c.lower() not in correct_letters_lower]
    seen: set[str] = set()
    unique_candidates = []
    for c in candidates:
        key = c.lower()
        if key not in seen:
            seen.add(key)
            unique_candidates.append(c)
    random.shuffle(unique_candidates)
    wrong_letters = unique_candidates[:wrong_letter_count]

    all_letters = correct_letters + wrong_letters
    random.shuffle(all_letters)

    primary_translation = word.translations[0]
    return BuildWordItemOut(
        word_id=word.id,
        translation=primary_translation.text,
        correct_word=correct_word,
        letters=all_letters,
        transcription=word.transcription,
        image_url=url_for_key(word.image_key),
        word_audio_url=url_for_key(word.word_audio_key),
        translation_audio_url=url_for_key(primary_translation.audio_key),
    )


def is_available(db: Session, user: User, dictionary_id: int, lesson_word_ids: list[int], threshold: int) -> bool:
    _, min_word_length, _ = get_build_word_settings(db)
    words = db.query(Word).filter(Word.id.in_(lesson_word_ids)).all()
    return any(len(w.word) >= min_word_length for w in words)


def build_round(db: Session, lesson: Lesson, threshold: int) -> BuildWordRoundOut:
    dictionary = db.get(Dictionary, lesson.dictionary_id)
    wrong_letter_count, min_word_length, case_sensitive = get_build_word_settings(db)
    words = [w for w in lesson_words_pending(db, lesson, threshold) if len(w.word) >= min_word_length]
    alphabet = dictionary.alphabet or "" if dictionary else ""

    items = [build_item(w, alphabet, wrong_letter_count) for w in words]
    return BuildWordRoundOut(
        dictionary_id=lesson.dictionary_id,
        available_count=len(words),
        case_sensitive=case_sensitive,
        items=items,
    )
