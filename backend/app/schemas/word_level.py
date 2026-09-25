from pydantic import BaseModel, Field


class WordLevelOut(BaseModel):
    id: int
    name: str
    min_points: int
    max_points: int | None
    order: int
    enabled: bool
    # How much a word at this level contributes to its own Priority Score
    # (see app/priority/) -- a GuYo-wide analytics layer on top of this
    # ladder, never read by anything that decides score/threshold/
    # achievements itself.
    priority_weight: float


class WordLevelCreateIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    min_points: int = Field(ge=0)
    max_points: int | None = Field(default=None, ge=0)
    enabled: bool = True
    order: int = 0
    priority_weight: float = 0


class WordLevelUpdateIn(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    min_points: int | None = Field(default=None, ge=0)
    max_points: int | None = Field(default=None, ge=0)
    clear_max_points: bool = False
    enabled: bool | None = None
    order: int | None = None
    priority_weight: float | None = None


class ReorderWordLevelsIn(BaseModel):
    word_level_ids: list[int]
