from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class DictionaryCreate(BaseModel):
    # No `name` field: the admin only picks/types a language, and the
    # dictionary's display name is derived from that server-side (see
    # resolve_dictionary_language_label).
    language: str = Field(min_length=1, max_length=64)
    # Optional at creation ("Алфавит задаётся при создании языка") -- can
    # also be left blank and filled in/edited later via DictionaryUpdate.
    alphabet: str | None = Field(default=None, max_length=256)


class DictionaryUpdate(BaseModel):
    # Both optional so a single PATCH only ever touches the field(s) it
    # actually sends -- publishing never clobbers the alphabet, and vice
    # versa. An empty-string alphabet clears it back to unset.
    is_published: bool | None = None
    alphabet: str | None = None


class DictionaryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    language: str
    is_published: bool
    alphabet: str | None
    created_at: datetime
    word_count: int = 0
