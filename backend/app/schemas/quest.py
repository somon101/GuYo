from typing import Any

from pydantic import BaseModel


class QuestOut(BaseModel):
    """Admin Web's view of one Quest definition."""

    id: int
    name: str
    word_level_id: int
    word_level_name: str
    exercise_key: str
    reward_points: int
    enabled: bool
    order: int


class ReorderQuestsIn(BaseModel):
    quest_ids: list[int]


class AvailableQuestOut(BaseModel):
    """One quest as shown to a user -- the definition plus whether they
    currently have an eligible, not-yet-used-today word for it in the
    given dictionary. `available=False` quests are still listed (so the
    user can see what exists), just not attemptable right now."""

    id: int
    name: str
    word_level_name: str
    exercise_key: str
    reward_points: int
    available: bool


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


class QuestAnswerOut(BaseModel):
    word_id: int
    score: int
    is_correct: bool
    # 0 when the answer was wrong, or when the word had already been used
    # in some other quest today (a race) -- never negative, never implies
    # a second grant happened.
    reward_granted: int
