"""Builds a ONE-TARGET-WORD round for each of the 5 word-scoped exercise
types, for a Quest. Reuses the exact same schemas and, wherever the
original Lesson builder already factored out a single-item helper
(build_word.build_item), the exact same function -- app/exercises/*.py
are otherwise written against a Lesson's fixed word SET, which a Quest
doesn't have (it targets exactly one word), so the remaining per-type
logic here is a deliberately thin, single-word adaptation of the same
Lesson logic in app/exercises/*.py, not a second competing implementation
of the exercise itself (the actual round SHAPES -- schemas -- and the
already-shared pools (get_learned_pool) are 100% reused, never
redefined).
"""

import random

from sqlalchemy.orm import Session

from app.core.storage import url_for_key
from app.exercises import build_word, listen_word, matching, speaking_word, true_or_false
from app.exercises.common import get_learned_pool
from app.models.dictionary import Dictionary
from app.models.user import User
from app.models.word import Word
from app.routers.words import word_to_out
from app.schemas.exercise import BuildWordRoundOut, ExerciseWordsOut, TrueOrFalseItemOut, TrueOrFalseRoundOut
from app.schemas.lesson import ListenWordItemOut, ListenWordOptionOut, ListenWordRoundOut, SpeakingWordItemOut, SpeakingWordRoundOut

# How many extra words (besides the quest's own target) pad a matching/
# listening board -- purely a board-size choice, not a rule from anywhere
# else in the app.
MAX_SIBLINGS = 3


def _siblings(db: Session, user: User, dictionary_id: int, threshold: int, target: Word, limit: int) -> list[Word]:
    pool = [w for w in get_learned_pool(db, user.id, dictionary_id, threshold) if w.id != target.id]
    random.shuffle(pool)
    return pool[:limit]


def is_quest_word_feasible(db: Session, user: User, dictionary_id: int, threshold: int, exercise_key: str, word: Word) -> bool:
    """Whether a round can actually be built for `word` with this
    exercise_key -- mirrors each exercise module's own `is_available`,
    adapted to a single target word instead of a whole lesson word set."""
    if exercise_key == matching.KEY:
        return bool(word.translations) and len(_siblings(db, user, dictionary_id, threshold, word, 1)) >= 1
    if exercise_key == true_or_false.KEY:
        return bool(word.translations)
    if exercise_key == build_word.KEY:
        _, min_word_length, _ = build_word.get_build_word_settings(db)
        return len(word.word) >= min_word_length
    if exercise_key == speaking_word.KEY:
        return True
    if exercise_key == listen_word.KEY:
        return bool(word.word_audio_key)
    return False


def build_matching_round(db: Session, user: User, dictionary_id: int, threshold: int, target: Word) -> ExerciseWordsOut:
    siblings = _siblings(db, user, dictionary_id, threshold, target, MAX_SIBLINGS)
    words = [w for w in [target, *siblings] if w.translations]
    return ExerciseWordsOut(
        dictionary_id=dictionary_id, exercise_key=matching.KEY, available_count=len(words), words=[word_to_out(w) for w in words]
    )


def build_true_or_false_round(db: Session, user: User, dictionary_id: int, threshold: int, target: Word) -> TrueOrFalseRoundOut:
    learned_pool = get_learned_pool(db, user.id, dictionary_id, threshold)
    real_text = target.translations[0].text
    show_real = random.random() < 0.5

    fake_candidates = []
    if not show_real:
        fake_candidates = [w for w in learned_pool if w.id != target.id and w.translations[0].text != real_text]

    if show_real or not fake_candidates:
        shown_text = real_text
        shown_audio = url_for_key(target.translations[0].audio_key)
        is_correct = True
    else:
        fake_word = random.choice(fake_candidates)
        shown_text = fake_word.translations[0].text
        shown_audio = url_for_key(fake_word.translations[0].audio_key)
        is_correct = False

    item = TrueOrFalseItemOut(
        word_id=target.id,
        original=target.word,
        transcription=target.transcription,
        image_url=url_for_key(target.image_key),
        word_audio_url=url_for_key(target.word_audio_key),
        shown_translation=shown_text,
        shown_translation_audio_url=shown_audio,
        is_correct=is_correct,
    )
    return TrueOrFalseRoundOut(dictionary_id=dictionary_id, available_count=1, items=[item])


def build_build_word_round(db: Session, dictionary_id: int, target: Word) -> BuildWordRoundOut:
    dictionary = db.get(Dictionary, dictionary_id)
    wrong_letter_count, _, case_sensitive = build_word.get_build_word_settings(db)
    alphabet = dictionary.alphabet or "" if dictionary else ""
    item = build_word.build_item(target, alphabet, wrong_letter_count)
    return BuildWordRoundOut(dictionary_id=dictionary_id, available_count=1, case_sensitive=case_sensitive, items=[item])


def build_speaking_word_round(db: Session, dictionary_id: int, target: Word) -> SpeakingWordRoundOut:
    item = SpeakingWordItemOut(
        word_id=target.id, word=target.word, transcription=target.transcription, image_url=url_for_key(target.image_key)
    )
    return SpeakingWordRoundOut(
        dictionary_id=dictionary_id, available_count=1, match_threshold=speaking_word.get_match_threshold(db), items=[item]
    )


def build_listen_word_round(db: Session, user: User, dictionary_id: int, threshold: int, target: Word) -> ListenWordRoundOut:
    option_count = listen_word.get_option_count(db)
    siblings = _siblings(db, user, dictionary_id, threshold, target, option_count - 1)
    options = [ListenWordOptionOut(word_id=target.id, word=target.word)] + [
        ListenWordOptionOut(word_id=w.id, word=w.word) for w in siblings
    ]
    random.shuffle(options)
    item = ListenWordItemOut(word_id=target.id, word_audio_url=url_for_key(target.word_audio_key), options=options)
    return ListenWordRoundOut(dictionary_id=dictionary_id, available_count=1, items=[item])


def build_round_for_quest(db: Session, user: User, dictionary_id: int, threshold: int, exercise_key: str, target: Word):
    if exercise_key == matching.KEY:
        return build_matching_round(db, user, dictionary_id, threshold, target)
    if exercise_key == true_or_false.KEY:
        return build_true_or_false_round(db, user, dictionary_id, threshold, target)
    if exercise_key == build_word.KEY:
        return build_build_word_round(db, dictionary_id, target)
    if exercise_key == speaking_word.KEY:
        return build_speaking_word_round(db, dictionary_id, target)
    if exercise_key == listen_word.KEY:
        return build_listen_word_round(db, user, dictionary_id, threshold, target)
    raise ValueError(f"Unknown exercise_key: {exercise_key}")
