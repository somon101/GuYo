"""Exercises: the shared foundation for turning a user's LEARNED words
(app/models/learning.py's LearnedWord -- never the full dictionary) into a
ready-to-play round, plus the admin-configurable word count each exercise
uses (app/models/exercise.py's ExerciseSettings, keyed by a plain string so
a future exercise needs no schema change).

"Правда или ложь" is the first exercise built on this; "Сопоставление" and
anything after it can reuse the exact same LearnedWord query and the same
per-exercise word_count knob later without any of this changing shape.
Nothing here duplicates Word -- every item just carries an existing
word_id, and the card fields come straight off the same Word row the
dictionary/editor/learning screens already use.
"""
import random

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin, get_current_user
from app.core.storage import url_for_key
from app.database import get_db
from app.models.dictionary import Dictionary
from app.models.exercise import ExerciseSettings
from app.models.learning import LearnedWord
from app.models.user import User
from app.models.word import Word
from app.routers.words import word_to_out
from app.schemas.exercise import (
    ExerciseSettingsIn,
    ExerciseSettingsOut,
    ExerciseWordsOut,
    TrueOrFalseItemOut,
    TrueOrFalseRoundOut,
)

router = APIRouter(tags=["exercises"])

TRUE_OR_FALSE_KEY = "true_or_false"
MATCHING_KEY = "matching"
DEFAULT_WORD_COUNT = 10


def _get_published_dictionary_or_404(db: Session, dictionary_id: int) -> Dictionary:
    dictionary = db.get(Dictionary, dictionary_id)
    if dictionary is None or not dictionary.is_published:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")
    return dictionary


def _get_word_count(db: Session, exercise_key: str) -> int:
    settings = db.query(ExerciseSettings).filter(ExerciseSettings.exercise_key == exercise_key).first()
    return settings.word_count if settings is not None else DEFAULT_WORD_COUNT


def _get_usable_learned_words(db: Session, user_id: int, dictionary_id: int) -> list[Word]:
    """Every Word the user has learned in this dictionary that actually has
    a translation to quiz/match against -- the ONE shared word source every
    exercise built on "learned words only" is meant to read from, never
    Word.dictionary_id directly."""
    learned_words = (
        db.query(Word)
        .join(LearnedWord, LearnedWord.word_id == Word.id)
        .filter(LearnedWord.user_id == user_id, Word.dictionary_id == dictionary_id)
        .all()
    )
    return [w for w in learned_words if w.translations]


def _pick_round_words(db: Session, usable_words: list[Word], exercise_key: str) -> list[Word]:
    """Randomly picks up to `exercise_key`'s admin-configured word_count
    words out of the already-usable pool -- the one place "how many, and
    which ones" is decided for any exercise built this way."""
    available_count = len(usable_words)
    if available_count == 0:
        return []
    word_count = _get_word_count(db, exercise_key)
    return random.sample(usable_words, k=min(word_count, available_count))


@router.get("/exercise-settings/{exercise_key}", response_model=ExerciseSettingsOut)
def get_exercise_settings(
    exercise_key: str, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    """Admin Web reads this to show the current word count -- falls back to
    DEFAULT_WORD_COUNT (never a 404) so an exercise works out of the box
    before an admin ever visits the settings page."""
    return ExerciseSettingsOut(exercise_key=exercise_key, word_count=_get_word_count(db, exercise_key))


@router.put("/exercise-settings/{exercise_key}", response_model=ExerciseSettingsOut)
def set_exercise_settings(
    exercise_key: str,
    payload: ExerciseSettingsIn,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    settings = db.query(ExerciseSettings).filter(ExerciseSettings.exercise_key == exercise_key).first()
    if settings is None:
        settings = ExerciseSettings(exercise_key=exercise_key, word_count=payload.word_count)
        db.add(settings)
    else:
        settings.word_count = payload.word_count
    db.commit()
    return ExerciseSettingsOut(exercise_key=exercise_key, word_count=payload.word_count)


@router.get("/dictionaries/{dictionary_id}/exercises/true-or-false", response_model=TrueOrFalseRoundOut)
def get_true_or_false_round(
    dictionary_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Builds one full round server-side: which learned words, and for each
    one whether the translation shown is real or borrowed from a different
    learned word. The client only ever renders what it's given and
    compares the user's tap to `is_correct` -- no word selection or
    true/false decision on-device, so a future UI change here can never
    drift from the actual rule.

    Word source is strictly LearnedWord for this (user, dictionary) --
    never Word.dictionary_id alone -- per the "learned words only" rule
    that's meant to hold for every exercise, this one included."""
    _get_published_dictionary_or_404(db, dictionary_id)

    usable_words = _get_usable_learned_words(db, user.id, dictionary_id)
    available_count = len(usable_words)
    selected = _pick_round_words(db, usable_words, TRUE_OR_FALSE_KEY)
    if not selected:
        return TrueOrFalseRoundOut(dictionary_id=dictionary_id, available_count=available_count, items=[])

    def primary_text(word: Word) -> str:
        return word.translations[0].text

    def primary_audio(word: Word) -> str | None:
        return url_for_key(word.translations[0].audio_key)

    items: list[TrueOrFalseItemOut] = []
    for word in selected:
        real_text = primary_text(word)
        show_real = available_count < 2 or random.random() < 0.5

        if not show_real:
            # Prefer a fake whose text actually differs from the real one,
            # so an accidental collision (two different words sharing a
            # translation) never makes a "Ложь" card display the exact
            # same string as the truth.
            fake_candidates = [w for w in usable_words if w.id != word.id and primary_text(w) != real_text]
            if not fake_candidates:
                fake_candidates = [w for w in usable_words if w.id != word.id]
        else:
            fake_candidates = []

        if show_real or not fake_candidates:
            shown_text, shown_audio, is_correct = real_text, primary_audio(word), True
        else:
            fake_word = random.choice(fake_candidates)
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

    return TrueOrFalseRoundOut(dictionary_id=dictionary_id, available_count=available_count, items=items)


@router.get(
    "/dictionaries/{dictionary_id}/exercises/{exercise_key}/learned-words",
    response_model=ExerciseWordsOut,
)
def get_exercise_learned_words(
    dictionary_id: int,
    exercise_key: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """The generic building block for an exercise that just needs N random
    already-learned words and does its own thing with them -- no per-item
    decision like True/False's real-or-fake translation choice.

    "Сопоставление" is the first consumer: its shuffle-into-two-columns and
    tap-to-match logic is entirely unchanged, only the word SOURCE changes
    from every word in the dictionary to this -- learned words, capped at
    this exercise's own admin-configured count. Any future exercise with
    the same "just give me some learned words" need can reuse this
    unmodified by picking its own `exercise_key`."""
    _get_published_dictionary_or_404(db, dictionary_id)
    usable_words = _get_usable_learned_words(db, user.id, dictionary_id)
    selected = _pick_round_words(db, usable_words, exercise_key)
    return ExerciseWordsOut(
        dictionary_id=dictionary_id,
        exercise_key=exercise_key,
        available_count=len(usable_words),
        words=[word_to_out(w) for w in selected],
    )
