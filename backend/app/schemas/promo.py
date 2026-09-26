from datetime import datetime

from pydantic import BaseModel, Field


class RedeemIn(BaseModel):
    # One field for both kinds: a code or a pasted link.
    code: str = Field(min_length=1, max_length=1000)


class RedeemOut(BaseModel):
    days: int
    premium_until: datetime
    kind: str
    is_first_link: bool
    message: str


# --- Admin ---------------------------------------------------------------------


class PromoCodeCreateIn(BaseModel):
    code: str = Field(min_length=1, max_length=40)
    days: int = Field(ge=1, le=1095)
    enabled: bool = True
    expires_at: datetime | None = None
    max_activations: int | None = Field(default=None, ge=1)
    note: str | None = Field(default=None, max_length=300)


class PromoCodeUpdateIn(BaseModel):
    """Only the fields sent are changed; sending `expires_at` or
    `max_activations` as null removes that restriction."""

    code: str | None = Field(default=None, min_length=1, max_length=40)
    days: int | None = Field(default=None, ge=1, le=1095)
    enabled: bool | None = None
    expires_at: datetime | None = None
    max_activations: int | None = Field(default=None, ge=1)
    note: str | None = Field(default=None, max_length=300)


class PromoCodeOut(BaseModel):
    id: int
    code: str
    days: int
    enabled: bool
    expires_at: datetime | None
    max_activations: int | None
    note: str | None
    activations: int
    created_at: datetime


class PromoLinkCreateIn(BaseModel):
    url: str = Field(min_length=3, max_length=1000)
    title: str | None = Field(default=None, max_length=200)
    repeat_days: int | None = Field(default=None, ge=1, le=1095)
    enabled: bool = True


class PromoLinkUpdateIn(BaseModel):
    """Only the fields sent are changed; `repeat_days` sent as null falls
    back to the global repeat reward."""

    url: str | None = Field(default=None, min_length=3, max_length=1000)
    title: str | None = Field(default=None, max_length=200)
    repeat_days: int | None = Field(default=None, ge=1, le=1095)
    enabled: bool | None = None


class PromoLinkOut(BaseModel):
    id: int
    url: str
    title: str | None
    repeat_days: int | None
    enabled: bool
    activations: int
    created_at: datetime


class PromoSettingsIn(BaseModel):
    promo_link_first_days: int = Field(ge=1, le=1095)
    promo_link_repeat_days: int = Field(ge=1, le=1095)


class PromoSettingsOut(PromoSettingsIn):
    pass


class PromoActivationOut(BaseModel):
    id: int
    user_id: int
    user_login: str
    user_public_id: int
    promo_code_id: int | None
    promo_link_id: int | None
    # The code itself, or the link's title (its URL when it has none).
    label: str
    days: int
    is_first_link: bool
    created_at: datetime
