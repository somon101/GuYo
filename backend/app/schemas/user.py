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
    `id` (never `login`, which is only credentials/display text), their
    avatar -- a real uploaded photo's URL, or null when the client should
    render its own generated default avatar instead -- and their current
    activity streak. Both avatar_key and the streak (UserActivityDay) live
    in Postgres, never on the device, so a login from a different phone
    sees the exact same values.

    `current_streak_days`, `lessons_completed` and `words_learned` all
    reuse app/achievements/conditions.py's own counters -- the SAME numbers
    the "Активность"/"Уроки"/"Слова" achievement condition_types are
    evaluated against -- never a second definition of any of them, and
    shown here even when no admin has configured a matching achievement at
    all."""

    id: int
    login: str
    avatar_url: str | None
    current_streak_days: int
    lessons_completed: int
    words_learned: int
