from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.models.dictionary import DictionaryLanguage


class DictionaryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=128)
    language: DictionaryLanguage


class DictionaryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    language: DictionaryLanguage
    created_at: datetime
    word_count: int = 0
