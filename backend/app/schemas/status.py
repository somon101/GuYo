from datetime import datetime

from pydantic import BaseModel, Field


class StatusEmojiOut(BaseModel):
    id: int
    name: str
    image_url: str | None
    enabled: bool
    order: int
    created_at: datetime


class StatusPhraseOut(BaseModel):
    id: int
    text: str
    enabled: bool
    order: int
    created_at: datetime


class StatusPhraseCreateIn(BaseModel):
    text: str = Field(min_length=1, max_length=60)
    enabled: bool = True


class StatusPhraseUpdateIn(BaseModel):
    text: str | None = Field(default=None, min_length=1, max_length=60)
    enabled: bool | None = None


class ReorderIn(BaseModel):
    ids: list[int]


class StatusEmojiOption(BaseModel):
    id: int
    name: str
    image_url: str | None


class StatusPhraseOption(BaseModel):
    id: int
    text: str


class MyStatusOut(BaseModel):
    """The user's current status as everyone sees it; a field is null
    when unset, or when the admin has since switched that item off."""

    emoji_id: int | None
    emoji_url: str | None
    phrase_id: int | None
    text: str | None


class StatusOptionsOut(BaseModel):
    """What the picker offers (enabled items, in the admin's order) and
    what the user has now."""

    emojis: list[StatusEmojiOption]
    phrases: list[StatusPhraseOption]
    mine: MyStatusOut


class MyStatusIn(BaseModel):
    """Both fields are always sent: null clears that part."""

    emoji_id: int | None = None
    phrase_id: int | None = None
