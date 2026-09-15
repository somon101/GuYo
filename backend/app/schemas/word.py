from datetime import datetime

from pydantic import BaseModel, ConfigDict


class WordTranslationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    language: str
    text: str
    audio_url: str | None


class WordOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    dictionary_id: int
    word: str
    transcription: str | None
    word_audio_url: str | None
    image_url: str | None
    quizlet: str | None
    created_at: datetime
    updated_at: datetime

    # Convenience fields mirroring the primary (first) translation, kept so
    # simple consumers -- the Flutter app included -- don't need to know
    # about the `translations` list at all.
    translation: str | None
    translation_audio_url: str | None

    # Full set of translations, one per language, for the admin editor.
    translations: list[WordTranslationOut]
