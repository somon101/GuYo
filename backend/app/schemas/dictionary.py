from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class DictionaryCreate(BaseModel):
    # No `name` field: the admin only picks/types a language, and the
    # dictionary's display name is derived from that server-side (see
    # resolve_dictionary_language_label).
    language: str = Field(min_length=1, max_length=64)


class DictionaryUpdate(BaseModel):
    is_published: bool


class DictionaryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    language: str
    is_published: bool
    created_at: datetime
    word_count: int = 0
