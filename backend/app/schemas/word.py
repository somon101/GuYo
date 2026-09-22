from datetime import datetime

from pydantic import BaseModel, ConfigDict


class WordTranslationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    language: str
    text: str
    audio_url: str | None


class WordFormOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    language: str
    text: str


class WordOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    dictionary_id: int
    word: str
    transcription: str | None
    word_audio_url: str | None
    image_url: str | None
    category_id: int | None
    category_name: str | None
    created_at: datetime
    updated_at: datetime

    # Convenience fields mirroring the primary (first) translation, kept so
    # simple consumers -- the Flutter app included -- don't need to know
    # about the `translations` list at all.
    translation: str | None
    translation_audio_url: str | None

    # Full set of translations, one per language, for the admin editor.
    translations: list[WordTranslationOut]

    # Grammatical forms, in insertion order, one list mixing all languages
    # -- the admin editor groups them by `language` for display.
    forms: list[WordFormOut]

    # This user's own progress on this word -- None everywhere word_to_out()
    # is called without a user in scope (matching.py, exercises.py,
    # quests/rounds.py, lessons.py, most of words.py). Only
    # learning.py's /learned-words populates these, by enriching the object
    # AFTER word_to_out() builds it, using word_levels' own
    # ordered_enabled_levels/level_for_score_in so the level shown here is
    # always the same one the rest of the app (Quests included) would pick
    # for this score -- never a second, parallel classification.
    score: int | None = None
    word_level_id: int | None = None
    word_level_name: str | None = None
