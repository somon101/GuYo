from pydantic import BaseModel, ConfigDict, Field

from app.schemas.word import WordOut


class ExerciseSettingsOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    exercise_key: str
    word_count: int


class ExerciseSettingsIn(BaseModel):
    word_count: int = Field(ge=1, le=100)


class TrueOrFalseItemOut(BaseModel):
    word_id: int
    original: str
    transcription: str | None
    image_url: str | None
    word_audio_url: str | None
    # Always the text actually shown on the card -- either the word's own
    # real translation, or one borrowed from a different learned word.
    shown_translation: str
    shown_translation_audio_url: str | None
    # True iff `shown_translation` is this word's own real translation.
    is_correct: bool


class TrueOrFalseRoundOut(BaseModel):
    dictionary_id: int
    # How many learned (and usable -- i.e. with at least one translation)
    # words existed to draw from. len(items) is min(admin word_count,
    # available_count); the client can use this to tell "fewer words than
    # configured" apart from "the configured count in full".
    available_count: int
    items: list[TrueOrFalseItemOut]


class ExerciseWordsOut(BaseModel):
    """The generic shape for any exercise that just needs N already-learned
    Word rows and does its own thing with them client-side (e.g.
    "Сопоставление", which only needs the words themselves to shuffle into
    two columns) -- no per-item decision like True/False's real-or-fake
    translation choice."""

    dictionary_id: int
    exercise_key: str
    available_count: int
    words: list[WordOut]
