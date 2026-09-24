from datetime import datetime

from pydantic import BaseModel, Field


class SloganOut(BaseModel):
    """Admin Web's view of one greeting line."""

    id: int
    text: str
    enabled: bool
    order: int
    created_at: datetime


class SloganCreateIn(BaseModel):
    text: str = Field(min_length=1, max_length=255)
    enabled: bool = True
    order: int = 0


class SloganUpdateIn(BaseModel):
    """Every field optional -- only what is sent is changed, so toggling a
    slogan off never rewrites its text."""

    text: str | None = Field(default=None, min_length=1, max_length=255)
    enabled: bool | None = None
    order: int | None = None


class ReorderSlogansIn(BaseModel):
    slogan_ids: list[int]


class TodaySloganOut(BaseModel):
    """The line the greeting shows. `text` is null when an admin has no
    enabled slogans at all -- a real state, not an error: the app falls
    back to its own built-in line rather than greeting the user with an
    empty second row."""

    text: str | None
