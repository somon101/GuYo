from pydantic import BaseModel, Field


class PrioritySettingsOut(BaseModel):
    weight_level: float
    weight_recent_errors: float
    weight_recency: float
    weight_stability: float
    window5_weight: float
    window10_weight: float
    window20_weight: float
    stability_window: int
    # Personal auto-quests -- see app/priority/quests_auto.py.
    personal_quest_min_attempts: int
    personal_quest_weak_error_rate: float
    personal_quest_min_words: int
    personal_quest_max_words: int
    personal_quest_reward_points: int


class PrioritySettingsIn(BaseModel):
    weight_level: float = Field(ge=0)
    weight_recent_errors: float = Field(ge=0)
    weight_recency: float = Field(ge=0)
    weight_stability: float = Field(ge=0)
    window5_weight: float = Field(ge=0)
    window10_weight: float = Field(ge=0)
    window20_weight: float = Field(ge=0)
    stability_window: int = Field(ge=1)
    personal_quest_min_attempts: int = Field(ge=1)
    personal_quest_weak_error_rate: float = Field(ge=0, le=1)
    personal_quest_min_words: int = Field(ge=1)
    personal_quest_max_words: int = Field(ge=1)
    personal_quest_reward_points: int = Field(ge=0)


class PriorityRecencyBandOut(BaseModel):
    id: int
    name: str
    min_days: int
    max_days: int | None
    contribution: float
    order: int
    enabled: bool


class PriorityRecencyBandCreateIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    min_days: int = Field(ge=0)
    max_days: int | None = Field(default=None, ge=0)
    contribution: float = 0
    enabled: bool = True
    order: int = 0


class PriorityRecencyBandUpdateIn(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    min_days: int | None = Field(default=None, ge=0)
    max_days: int | None = Field(default=None, ge=0)
    clear_max_days: bool = False
    contribution: float | None = None
    enabled: bool | None = None
    order: int | None = None


class PriorityStabilityBandOut(BaseModel):
    id: int
    name: str
    min_percent: int
    max_percent: int
    contribution: float
    order: int
    enabled: bool


class PriorityStabilityBandCreateIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    min_percent: int = Field(ge=0, le=100)
    max_percent: int = Field(ge=0, le=100)
    contribution: float = 0
    enabled: bool = True
    order: int = 0


class PriorityStabilityBandUpdateIn(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    min_percent: int | None = Field(default=None, ge=0, le=100)
    max_percent: int | None = Field(default=None, ge=0, le=100)
    contribution: float | None = None
    enabled: bool | None = None
    order: int | None = None


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
