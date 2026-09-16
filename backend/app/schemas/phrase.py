from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class PhraseCategoryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=128)


class PhraseCategoryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    dictionary_id: int
    name: str
    created_at: datetime
    phrase_count: int = 0


class PhraseOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    dictionary_id: int
    category_id: int | None
    category_name: str | None
    original: str
    transcription: str | None
    translation_tg: str
    original_audio_url: str | None
    translation_audio_url: str | None
    created_at: datetime
    updated_at: datetime
