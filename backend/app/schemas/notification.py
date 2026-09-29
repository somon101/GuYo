from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class NotificationOut(BaseModel):
    """One message in a user's inbox.

    `source` is provenance -- "manual" for an admin message, and whatever
    a future automatic rule stamps. The client shows the same row either
    way; it is here so an admin can see why something was sent."""

    id: int
    title: str | None
    body: str
    source: str
    is_read: bool
    read_at: datetime | None
    created_at: datetime


class NotificationListOut(BaseModel):
    """The inbox plus the one number the bell's indicator is drawn from,
    so the client never has to count unread messages itself."""

    unread_count: int
    items: list[NotificationOut]


class UnreadCountOut(BaseModel):
    """What the bell's dot is drawn from, on its own so the app bar never
    has to fetch the whole inbox."""

    unread_count: int


class NotificationSendIn(BaseModel):
    """What an admin fills in to write to one user."""

    user_id: int
    title: str | None = Field(default=None, max_length=120)
    body: str = Field(min_length=1, max_length=2000)


class AdminNotificationOut(NotificationOut):
    """What the admin sees back: the same message, plus who received it,
    so a sent-messages list reads without a second lookup."""

    user_id: int
    user_login: str


class PushTokenIn(BaseModel):
    token: str = Field(min_length=10, max_length=512)


ReminderKind = Literal["inactivity", "streak_risk", "streak_milestone"]


class ReminderRuleIn(BaseModel):
    kind: ReminderKind
    days: int = Field(ge=1, le=3650)
    title: str | None = Field(default=None, max_length=120)
    body: str = Field(min_length=1, max_length=1000)
    enabled: bool = True


class ReminderRuleOut(ReminderRuleIn):
    id: int


class ReminderSettingsIn(BaseModel):
    streak_risk_hour: int = Field(ge=0, le=23)
    default_hour: int = Field(ge=0, le=23)


class RemindersOut(BaseModel):
    settings: ReminderSettingsIn
    rules: list[ReminderRuleOut]
