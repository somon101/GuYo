from datetime import date, datetime

from pydantic import BaseModel, Field, field_validator

from app.models.rating import RESET_MODE_FIXED, RESET_MODE_PERCENT


class RatingSettingsOut(BaseModel):
    points_per_learned_word: int
    season_reset_mode: str
    season_reset_value: int


class RatingSettingsIn(BaseModel):
    points_per_learned_word: int = Field(ge=0)
    season_reset_mode: str
    season_reset_value: int = Field(ge=0)

    @field_validator("season_reset_mode")
    @classmethod
    def _mode_must_be_known(cls, v: str) -> str:
        if v not in (RESET_MODE_FIXED, RESET_MODE_PERCENT):
            raise ValueError(f"season_reset_mode must be one of '{RESET_MODE_FIXED}'/'{RESET_MODE_PERCENT}'")
        return v

    @field_validator("season_reset_value")
    @classmethod
    def _percent_value_in_range(cls, v: int, info) -> int:
        # A fixed reset has no natural upper bound (it's just a point
        # count), but a percent reset above 100 is meaningless.
        mode = info.data.get("season_reset_mode")
        if mode == RESET_MODE_PERCENT and v > 100:
            raise ValueError("a percent reset value must be between 0 and 100")
        return v


class RankOut(BaseModel):
    """Admin Web's view of one Rank definition -- every field."""

    id: int
    name: str
    min_points: int
    max_points: int | None
    icon_url: str | None
    color: str
    order: int
    enabled: bool


class RankPublicOut(BaseModel):
    """The Profile screen's view of a rank -- just enough to render it,
    never the admin-only `enabled`/`order` fields."""

    id: int
    name: str
    icon_url: str | None
    color: str
    min_points: int
    max_points: int | None


class ReorderRanksIn(BaseModel):
    rank_ids: list[int]


class SeasonOut(BaseModel):
    id: int
    name: str
    start_date: date
    end_date: date | None
    status: str


class SeasonCreateIn(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    start_date: date | None = None


class SeasonHistoryOut(BaseModel):
    """One user's frozen result for one completed season -- never
    recomputed from the season's current state, since a season's own
    result is fixed the moment it ends (see app/rating/service.py's
    end_season)."""

    season_id: int
    season_name: str
    points: int
    rank: RankPublicOut | None
    ended_at: datetime


class UserRatingOut(BaseModel):
    """Everything the Profile screen needs for its "Рейтинг" block, in one
    round trip: current points, current season, current rank, the next
    rank up (for a progress bar), and past seasons' frozen results. The
    backend decides all of it -- Flutter only renders."""

    total_points: int
    season: SeasonOut | None
    rank: RankPublicOut | None
    next_rank: RankPublicOut | None
    points_to_next_rank: int | None
    history: list[SeasonHistoryOut]
