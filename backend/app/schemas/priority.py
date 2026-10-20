from pydantic import BaseModel, Field


class PrioritySettingsOut(BaseModel):
    # Personal auto-quests -- see app/priority/quests_auto.py.
    personal_quest_min_attempts: int
    personal_quest_weak_error_rate: float
    personal_quest_min_words: int
    personal_quest_max_words: int
    personal_quest_reward_points: int
    # How many "critical" words must accumulate before an adaptive lesson is
    # built automatically (see app/priority/lessons.py).
    adaptive_lesson_min_words: int
    memory_target_retention: float
    memory_critical_below: float
    memory_high_below: float
    memory_minimal_above: float


class PrioritySettingsIn(BaseModel):
    personal_quest_min_attempts: int = Field(ge=1)
    personal_quest_weak_error_rate: float = Field(ge=0, le=1)
    personal_quest_min_words: int = Field(ge=1)
    personal_quest_max_words: int = Field(ge=1)
    personal_quest_reward_points: int = Field(ge=0)
    adaptive_lesson_min_words: int = Field(default=5, ge=1, le=50)
    memory_target_retention: float = Field(default=0.9, gt=0, lt=1)
    memory_critical_below: float = Field(default=0.7, gt=0, lt=1)
    memory_high_below: float = Field(default=0.85, gt=0, lt=1)
    memory_minimal_above: float = Field(default=0.95, gt=0, lt=1)


class PriorityLevelBandOut(BaseModel):
    id: int
    name: str
    min_score: float
    max_score: float | None
    order: int
    enabled: bool


class PriorityLevelBandCreateIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    min_score: float
    max_score: float | None = None
    enabled: bool = True
    order: int = 0


class PriorityLevelBandUpdateIn(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    min_score: float | None = None
    max_score: float | None = None
    clear_max_score: bool = False
    enabled: bool | None = None
    order: int | None = None


class ReorderPriorityBandsIn(BaseModel):
    band_ids: list[int]
