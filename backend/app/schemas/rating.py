from datetime import date, datetime

from pydantic import BaseModel, Field, field_validator

from app.core.storage import url_for_key
from app.models.rating import RESET_MODE_FIXED, RESET_MODE_PERCENT, Rank


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


def rank_public_out(rank: Rank | None) -> RankPublicOut | None:
    """The one place a Rank ORM row becomes a RankPublicOut -- shared by
    every user-facing endpoint that shows a rank (app/routers/users.py's
    /me/rating, app/routers/rating.py's leaderboards), never redefined
    per router."""
    if rank is None:
        return None
    return RankPublicOut(
        id=rank.id, name=rank.name, icon_url=url_for_key(rank.icon_key), color=rank.color,
        min_points=rank.min_points, max_points=rank.max_points,
    )


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


class LeaderboardEntryOut(BaseModel):
    """One row of a leaderboard -- `position` is this row's 1-based rank
    within THIS list (own-rank or global), never a global user id ordering.
    `rank` is only meaningful on the global board (every row of an
    own-rank board shares the same rank by construction, so the client
    doesn't need to re-render it per row there, but it's included on both
    for a uniform shape)."""

    position: int
    user_id: int
    login: str
    avatar_url: str | None
    total_points: int
    rank: RankPublicOut | None
    is_me: bool


class LeaderboardOut(BaseModel):
    # None when the requesting user has no current rank at all (no ranks
    # configured, or a gap in the ladder) -- entries is then always empty
    # for the own-rank board (there's no range to match against), while
    # the global board can still be non-empty.
    rank: RankPublicOut | None
    entries: list[LeaderboardEntryOut]


class UserRatingOut(BaseModel):
    """Everything the Profile screen needs for its "Рейтинг" block, in one
    round trip: current points, current season, current rank, the next
    rank up (for a progress bar), and past seasons' frozen results. The
    backend decides all of it -- Flutter only renders.

    `points_per_learned_word` is the SAME RatingSettings value
    award_word_points_if_new already grants on every newly-learned word
    (app/rating/service.py) -- included here so the "Квесты" screen's
    always-visible "изучение новых слов" system tile can show the real
    configured reward without a second settings surface.

    `rank_position` is this user's own real 1-based place among everyone
    currently in the SAME rank (see app/rating/service.py's
    rank_position_for_user) -- the same ordering the "Топ-100" own-rank
    leaderboard itself uses, never capped at 100. None when the user has
    no current rank at all (no ranks configured, or a gap in the ladder).
    """

    total_points: int
    season: SeasonOut | None
    rank: RankPublicOut | None
    next_rank: RankPublicOut | None
    points_to_next_rank: int | None
    history: list[SeasonHistoryOut]
    points_per_learned_word: int
    rank_position: int | None


class GrantRatingPointsIn(BaseModel):
    # Signed -- a negative value withdraws points (still floored at 0 by
    # grant_rating_points' own caller-independent behavior is NOT assumed
    # here; see admin_rating.py's endpoint for the actual clamp), same
    # "delta, not an absolute" shape grant_rating_points itself already
    # takes everywhere else it's called (Quest rewards).
    points: int


class UserPointsOut(BaseModel):
    """Just enough to confirm an admin rating adjustment landed -- not the
    full UserRatingOut (no season/rank/history needed for this one call)."""

    user_id: int
    total_points: int
