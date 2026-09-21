from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.achievements.icons import ACHIEVEMENT_ICONS
from app.achievements.conditions import CONDITION_TYPES


class AchievementOut(BaseModel):
    """Admin Web's view of one Achievement definition -- every field,
    including ones a regular user never needs (enabled, order)."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    description: str
    icon: str
    condition_type: str
    condition_value: int
    enabled: bool
    order: int


class AchievementIn(BaseModel):
    title: str = Field(min_length=1, max_length=255)
    description: str = Field(min_length=1, max_length=500)
    icon: str
    condition_type: str
    condition_value: int = Field(ge=1)
    enabled: bool = True
    order: int = 0

    @field_validator("icon")
    @classmethod
    def _icon_must_be_known(cls, v: str) -> str:
        if v not in ACHIEVEMENT_ICONS:
            raise ValueError(f"Unknown icon '{v}' -- must be one of {sorted(ACHIEVEMENT_ICONS)}")
        return v

    @field_validator("condition_type")
    @classmethod
    def _condition_type_must_be_known(cls, v: str) -> str:
        if v not in CONDITION_TYPES:
            raise ValueError(f"Unknown condition_type '{v}' -- must be one of {sorted(CONDITION_TYPES)}")
        return v


class UserAchievementOut(BaseModel):
    """The Profile screen's view of one achievement: the definition plus
    this specific user's own status against it -- earned or not, and (for
    the ones not yet earned) their current progress toward it, so the UI
    can show e.g. "7 / 10" without a second round trip."""

    id: int
    title: str
    description: str
    icon: str
    condition_type: str
    condition_value: int
    earned: bool
    earned_at: datetime | None
    current_value: int


class AchievementIconOut(BaseModel):
    id: str
    emoji: str


class ConditionTypeOut(BaseModel):
    id: str
    label: str
