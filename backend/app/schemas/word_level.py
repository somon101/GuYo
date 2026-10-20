from pydantic import BaseModel, Field


class WordLevelOut(BaseModel):
    id: int
    name: str
    # How many days the memory must hold for a word to be at this level.
    min_days: float = 0
    order: int
    enabled: bool
    # Always 0 / null: words have no points any more. Only app builds from
    # before Oct 20, 2026 read these (as required fields).
    min_points: int = 0
    max_points: int | None = None


class WordLevelCreateIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    min_days: float = Field(default=0, ge=0)
    enabled: bool = True
    order: int = 0


class WordLevelUpdateIn(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    min_days: float | None = Field(default=None, ge=0)
    enabled: bool | None = None
    order: int | None = None


class ReorderWordLevelsIn(BaseModel):
    word_level_ids: list[int]
