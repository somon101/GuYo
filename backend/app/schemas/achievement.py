from datetime import datetime

from pydantic import BaseModel, ConfigDict


class AchievementOut(BaseModel):
    """Admin Web's view of one Achievement definition -- every field,
    including ones a regular user never needs (enabled, order,
    visibility/show_before_unlock)."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    description: str
    icon_url: str | None
    color: str
    condition_type: str
    condition_value: int
    enabled: bool
    visibility: str
    show_before_unlock: bool
    order: int


class UserAchievementOut(BaseModel):
    """The Profile screen's view of one achievement: the definition plus
    this specific user's own status against it.

    `title`/`description`/`condition_type`/`condition_value`/
    `current_value` come back as null for an achievement the user hasn't
    earned yet AND that's `visibility=hidden` -- the backend itself
    withholds what the condition even is, not just the client's styling,
    so a user can't discover a hidden condition by inspecting the network
    response. The client renders that as a generic locked/mystery tile
    (dimmed real icon, "Скрытое достижение" / "Условие неизвестно") purely
    from `title is None`, never by re-deriving hidden-ness itself.

    A `hidden` + `show_before_unlock=False` achievement the user hasn't
    earned is left out of the list entirely (see app/routers/users.py)
    rather than represented here at all."""

    id: int
    title: str | None
    description: str | None
    icon_url: str | None
    color: str
    condition_type: str | None
    condition_value: int | None
    current_value: int | None
    earned: bool
    earned_at: datetime | None


class ConditionTypeOut(BaseModel):
    id: str
    label: str


class ReorderIn(BaseModel):
    """The chain's full new order, front to back -- every existing
    achievement id must appear exactly once (see app/routers/
    admin_achievements.py's reorder_achievements)."""

    achievement_ids: list[int]
