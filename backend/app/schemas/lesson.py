from pydantic import BaseModel, Field, model_validator

from app.schemas.word import WordOut


class CreateLessonIn(BaseModel):
    """Exactly one of `word_ids` (ручной выбор) or `random_count` (случайный
    выбор) must be given -- both pick from the same pool (this dictionary's
    not-yet-learned words), capped at 15 either way."""

    dictionary_id: int
    word_ids: list[int] | None = Field(default=None, max_length=15)
    random_count: int | None = Field(default=None, ge=1, le=15)

    @model_validator(mode="after")
    def _exactly_one_selection_mode(self) -> "CreateLessonIn":
        if (self.word_ids is None) == (self.random_count is None):
            raise ValueError("Specify exactly one of word_ids or random_count")
        if self.word_ids is not None and len(self.word_ids) == 0:
            raise ValueError("word_ids must contain at least 1 word")
        return self


class LessonWordOut(BaseModel):
    word_id: int
    word: str
    translation: str | None
    score: int
    is_learned: bool


class LessonOut(BaseModel):
    id: int
    dictionary_id: int
    number: int
    is_completed: bool
    exercise_keys: list[str]
    words: list[LessonWordOut]


class LessonSummaryOut(BaseModel):
    """One row of a dictionary's full lesson history (see GET
    /dictionaries/{id}/lessons) -- everything the "Уроки" chain screen
    needs to render one link (number, status, a lightweight progress
    count) without fetching every lesson's full word list up front."""

    id: int
    number: int
    is_completed: bool
    word_count: int
    learned_count: int


class LessonListOut(BaseModel):
    dictionary_id: int
    lessons: list[LessonSummaryOut]


class LessonCandidateWordsOut(BaseModel):
    """The pool a new lesson's word picker (random or manual) draws from --
    every not-yet-learned word (WordProgress.score below the admin's
    threshold, or no progress row at all) in this dictionary."""

    dictionary_id: int
    available_count: int
    words: list[WordOut]


class SubmitAnswerIn(BaseModel):
    word_id: int
    is_correct: bool


class SubmitAnswerOut(BaseModel):
    word_id: int
    score: int
    is_learned: bool
    lesson_completed: bool


class LearningSettingsOut(BaseModel):
    threshold_score: int


class LearningSettingsIn(BaseModel):
    threshold_score: int = Field(ge=0, le=100)


class SpeakingWordItemOut(BaseModel):
    word_id: int
    word: str
    transcription: str | None
    image_url: str | None


class SpeakingWordRoundOut(BaseModel):
    dictionary_id: int
    available_count: int
    # Minimum recognized-text-vs-target similarity (0-100) the client must
    # require to accept a spoken answer as correct -- the admin's own
    # "speech_match_threshold" setting, carried on the round itself so the
    # client never has to fetch admin settings separately (same pattern as
    # BuildWordRoundOut.case_sensitive).
    match_threshold: int
    items: list[SpeakingWordItemOut]


class ListenWordOptionOut(BaseModel):
    word_id: int
    word: str


class ListenWordItemOut(BaseModel):
    word_id: int
    word_audio_url: str | None
    options: list[ListenWordOptionOut]


class ListenWordRoundOut(BaseModel):
    dictionary_id: int
    available_count: int
    items: list[ListenWordItemOut]
