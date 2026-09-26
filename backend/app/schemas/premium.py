from datetime import datetime

from pydantic import BaseModel, Field


class LessonQuotaOut(BaseModel):
    """Where the user stands against the lesson limits. A null limit means
    unlimited; `remaining` is the tighter of the two, null when neither
    applies. `blocked_by` is "day" or "week" while no lesson can be
    created, and `resets_at` is when that ends."""

    daily_limit: int | None
    daily_used: int
    weekly_limit: int | None
    weekly_used: int
    remaining: int | None
    blocked_by: str | None
    resets_at: datetime | None


class PremiumStatusOut(BaseModel):
    """Everything the app's Premium screen and the home screen's lesson
    counter need, in one round trip.

    `public_id` is here because the Premium screen asks the user to put it
    in the transfer's comment -- it is how the admin finds who paid.
    `adaptive_lessons_premium_only`/`personal_quests_premium_only` let the
    screen list only the benefits that really are Premium-only right
    now."""

    is_premium: bool
    premium_until: datetime | None
    public_id: int
    price_text: str
    payment_instructions: str
    adaptive_lessons_premium_only: bool
    personal_quests_premium_only: bool
    lessons: LessonQuotaOut


class PremiumSettingsIn(BaseModel):
    free_daily_lesson_limit: int | None = Field(default=None, ge=0)
    free_weekly_lesson_limit: int | None = Field(default=None, ge=0)
    premium_daily_lesson_limit: int | None = Field(default=None, ge=0)
    premium_weekly_lesson_limit: int | None = Field(default=None, ge=0)
    adaptive_lessons_premium_only: bool
    personal_quests_premium_only: bool
    price_text: str = Field(default="", max_length=200)
    payment_instructions: str = Field(default="", max_length=4000)


class PremiumSettingsOut(PremiumSettingsIn):
    pass


class GrantPremiumIn(BaseModel):
    # Up to three years in one go -- enough for any real plan, and a guard
    # against a typo like 3650.
    days: int = Field(ge=1, le=1095)
    note: str | None = Field(default=None, max_length=500)


class PremiumGrantOut(BaseModel):
    id: int
    user_id: int
    starts_at: datetime
    ends_at: datetime
    days: int
    source: str
    note: str | None
    granted_by_admin_login: str | None
    revoked_at: datetime | None
    created_at: datetime


class PremiumUserOut(BaseModel):
    """One row of Admin Web's subscriber list: the account, and whether
    and until when it has Premium right now."""

    user_id: int
    public_id: int
    login: str
    first_name: str | None
    last_name: str | None
    is_premium: bool
    premium_until: datetime | None
