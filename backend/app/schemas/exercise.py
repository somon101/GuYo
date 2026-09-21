from pydantic import BaseModel, ConfigDict, Field

from app.schemas.word import WordOut


class ExerciseSettingsOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    exercise_key: str
    word_count: int
    # Only meaningful for exercises that use them (currently "build_word");
    # null for every other exercise_key.
    wrong_letter_count: int | None = None
    min_word_length: int | None = None
    case_sensitive: bool | None = None
    # How much a right/wrong answer to this exercise moves a word's
    # WordProgress.score (see app/models/word_progress.py). Null means "use
    # this exercise_key's own code-level default" (see
    # app/exercises/common.py's DEFAULT_POINTS), same fallback pattern as
    # the fields above.
    correct_points: int | None = None
    incorrect_points: int | None = None
    # Whether this exercise_key can be picked for a new Lesson at all. Null
    # means enabled (same "unset = working default" convention as every
    # other field here) -- see app/exercises/__init__.py.
    enabled: bool | None = None
    # Only meaningful for "listen_word" (how many word choices one round
    # shows); null for every other exercise_key.
    option_count: int | None = None
    # Only meaningful for "speaking_word" (0-100 minimum text-similarity to
    # accept a spoken answer); null for every other exercise_key.
    speech_match_threshold: int | None = None


class ExerciseSettingsIn(BaseModel):
    word_count: int = Field(ge=1, le=100)
    wrong_letter_count: int | None = Field(default=None, ge=0, le=20)
    min_word_length: int | None = Field(default=None, ge=1, le=50)
    case_sensitive: bool | None = None
    correct_points: int | None = Field(default=None, ge=0, le=100)
    incorrect_points: int | None = Field(default=None, ge=0, le=100)
    enabled: bool | None = None
    option_count: int | None = Field(default=None, ge=2, le=10)
    speech_match_threshold: int | None = Field(default=None, ge=0, le=100)


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


class BuildWordItemOut(BaseModel):
    word_id: int
    translation: str
    # The word to build, exactly as stored (real casing/duplicates
    # preserved) -- the client compares the assembled letters against this
    # position by position; whether that comparison is case-sensitive is
    # `BuildWordRoundOut.case_sensitive`, not decided per item.
    correct_word: str
    # Every letter the player can tap: the word's own letters (with their
    # real multiplicity) plus the configured number of wrong distractor
    # letters, already shuffled together. Never fewer distractors than
    # configured only because the alphabet couldn't supply enough distinct
    # ones -- see get_build_word_round.
    letters: list[str]
    transcription: str | None
    image_url: str | None
    word_audio_url: str | None
    translation_audio_url: str | None


class BuildWordRoundOut(BaseModel):
    dictionary_id: int
    available_count: int
    case_sensitive: bool
    items: list[BuildWordItemOut]
