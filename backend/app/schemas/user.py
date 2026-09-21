from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class UserCreate(BaseModel):
    login: str = Field(min_length=3, max_length=64)
    password: str = Field(min_length=4, max_length=128)


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    login: str
    created_at: datetime


class UserProfileOut(BaseModel):
    """The Profile screen's own view of the current user: their permanent
    `id` (never `login`, which is only credentials/display text), and
    their avatar -- a real uploaded photo's URL, or null when the client
    should render its own generated default avatar instead."""

    id: int
    login: str
    avatar_url: str | None
