from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class CategoryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=128)


class CategoryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    dictionary_id: int
    name: str
    created_at: datetime
    word_count: int = 0
    # Resolved from icon_key by the router (never the raw key) -- null
    # when no icon was uploaded, which is the client's cue to draw its
    # own generic folder icon instead.
    icon_url: str | None = None
