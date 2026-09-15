from datetime import datetime

from pydantic import BaseModel, ConfigDict


class WordOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    dictionary_id: int
    word: str
    translation: str
    transcription: str | None
    word_audio_url: str | None
    translation_audio_url: str | None
    image_url: str | None
    created_at: datetime
    updated_at: datetime
