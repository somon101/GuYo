from typing import Any

from pydantic import BaseModel

from app.schemas.rating import RankPublicOut, SeasonOut


class QuestOut(BaseModel):
    """Admin Web's view of one Quest definition."""

    id: int
    name: str
    word_level_id: int
    word_level_name: str
    exercise_key: str
    reward_points: int
    daily_target: int
    enabled: bool
    order: int


class ReorderQuestsIn(BaseModel):
    quest_ids: list[int]


class AvailableQuestOut(BaseModel):
    """One quest as shown to a user -- the definition plus whether they
    currently have an eligible, not-yet-used-today word for it in the
    given dictionary. `available=False` quests are still listed (so the
    user can see what exists), just not attemptable right now.

    `completed_today` counts this quest's own UserQuestWordDay rows for
    today, i.e. how many words it has successfully consumed since the
    daily reset; `is_done_today` is simply that count reaching
    `daily_target`. Neither is stored anywhere -- both are counted from
    the rows the quest flow already writes."""

    id: int
    name: str
    word_level_name: str
    exercise_key: str
    reward_points: int
    available: bool
    daily_target: int
    completed_today: int
    is_done_today: bool


class QuestRoundOut(BaseModel):
    """A round for exactly one target word. `payload` is the SAME Out
    schema Lessons already use for this exercise_key (ExerciseWordsOut /
    TrueOrFalseRoundOut / BuildWordRoundOut / SpeakingWordRoundOut /
    ListenWordRoundOut, dumped to a plain dict) -- the client already
    knows how to parse each shape from the Lessons flow and picks the
    right parser by `exercise_key` here, exactly like it already picks
    the right screen by exercise_key for Lessons."""

    quest_id: int
    word_id: int
    exercise_key: str
    payload: dict[str, Any]


class QuestAnswerIn(BaseModel):
    word_id: int
    is_correct: bool


class SeasonQuestOverviewOut(BaseModel):
    """Everything the home screen's "Квесты сезона" block and the season
    quests screen render, in one round trip.

    A read-only VIEW, not a system of its own: every number below is
    counted from tables that already exist -- the active Season
    (app/rating/), UserRating/Rank (the same rank_position the Profile
    screen shows), UserWordPoints, UserQuestWordDay and Quest. Nothing
    here grants points, writes progress, or defines a second notion of
    "completed".
    """

    # The active season, or null when no season is running right now.
    # `days_left` and `days_total` are both null for a season with no
    # scheduled end (it ends when an admin says so, so there is neither a
    # countdown nor a range to show). Together they are the season's own
    # timeline: how much of it is gone and how much is left -- deliberately
    # NOT the same thing as quest progress, which is counted below.
    season: SeasonOut | None
    days_left: int | None
    days_total: int | None

    # Rating points this user earned TODAY: the words they learned plus
    # the quest rewards they collected, on the same Asia/Dushanbe day
    # boundary quests themselves reset on.
    points_today: int
    total_points: int
    rank: RankPublicOut | None
    # The user's real 1-based place within their own rank -- the very same
    # number GET /users/me/rating reports, never a second calculation.
    rank_position: int | None

    # How many of the enabled quests have reached their daily target
    # today, out of how many exist.
    quests_done_today: int
    quests_total: int

    # The permanent "изучение новых слов" quest: the reward each newly
    # learned word grants right now, and how many the user has learned
    # today. It has no attempt flow of its own -- the reward fires
    # wherever a word is first learned.
    points_per_learned_word: int
    words_learned_today: int

    # Every enabled quest, exactly as GET /quests lists them.
    quests: list[AvailableQuestOut]


class QuestAnswerOut(BaseModel):
    word_id: int
    score: int
    is_correct: bool
    # 0 when the answer was wrong, or when the word had already been used
    # in some other quest today (a race) -- never negative, never implies
    # a second grant happened.
    reward_granted: int
