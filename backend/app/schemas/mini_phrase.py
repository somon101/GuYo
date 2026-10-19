from datetime import datetime

from pydantic import BaseModel, Field

# --- What the app gets ------------------------------------------------------


class MiniPhraseSegmentOut(BaseModel):
    """One piece of the rendered explanation. `kind` is "text", "part",
    "phrase" or "translation"; `role` lets the app colour a part."""

    kind: str
    text: str
    role: str | None = None


class MiniPhrasePartOut(BaseModel):
    position: int
    text: str
    word_id: int
    role: str | None = None
    # The dictionary translation of this part's word, in the reader's language.
    translation: str | None = None


class MiniPhraseTileOut(BaseModel):
    """An extra (wrong) tile for "Собери фразу"."""

    text: str
    word_id: int | None = None


class MiniPhraseOut(BaseModel):
    id: int
    dictionary_id: int
    text: str
    translation: str | None = None
    audio_url: str | None = None
    template_kind: str
    parts: list[MiniPhrasePartOut]
    explanation: list[MiniPhraseSegmentOut]
    distractors: list[MiniPhraseTileOut] = []


class MiniPhraseAnswerIn(BaseModel):
    # The tiles in the order the learner placed them.
    answer: list[str] = Field(max_length=50)
    # Set when answered inside a lesson.
    lesson_id: int | None = None


class MiniPhraseAnswerOut(BaseModel):
    correct: bool
    points_awarded: int
    correct_text: str


# --- Admin ------------------------------------------------------------------


class MiniPhraseRoleOut(BaseModel):
    id: str
    label: str


class MiniPhraseTemplateIn(BaseModel):
    name: str = Field(min_length=1, max_length=128)
    kind: str = "ordered_parts"
    # The studied language this template belongs to (its phrases are in it).
    language: str | None = None
    # Explanations by reading language, for every language in the database
    # ({"ru": ..., "tg": ..., "en": ...}). The three old fields are still
    # accepted from older pages and mean the same as their keys here.
    explanations: dict[str, str] | None = None
    explanation_ru: str | None = None
    explanation_tg: str | None = None
    explanation_uz: str | None = None
    distractor_count: int = Field(default=2, ge=0, le=4)
    enabled: bool = True


class MiniPhraseTemplateOut(MiniPhraseTemplateIn):
    id: int
    usage_count: int = 0


class MiniPhrasePartIn(BaseModel):
    text: str = Field(min_length=1, max_length=255)
    word_id: int
    word_form_id: int | None = None
    role: str | None = None


class MiniPhraseIn(BaseModel):
    template_id: int | None = None
    text: str = Field(min_length=1, max_length=500)
    # The studied language the phrase is written in; None keeps the current
    # one (or the dictionary's language for a new phrase).
    language: str | None = None
    # Hints by reading language, for every language in the database. The three
    # old fields are still accepted and mean the same as their keys here.
    translations: dict[str, str] | None = None
    translation_tg: str | None = Field(default=None, max_length=500)
    translation_uz: str | None = Field(default=None, max_length=500)
    translation_en: str | None = Field(default=None, max_length=500)
    enabled: bool = True
    parts: list[MiniPhrasePartIn] = Field(min_length=1, max_length=20)


class MiniPhrasePartAdminOut(BaseModel):
    position: int
    text: str
    word_id: int
    word: str
    word_form_id: int | None = None
    word_form_text: str | None = None
    role: str | None = None
    word_role: str | None = None


class MiniPhraseAdminOut(BaseModel):
    id: int
    dictionary_id: int
    template_id: int | None
    template_name: str | None
    text: str
    language: str | None = None
    translations: dict[str, str] = {}
    translation_tg: str
    translation_uz: str | None
    translation_en: str | None
    enabled: bool
    parts: list[MiniPhrasePartAdminOut]
    created_at: datetime


class SuggestPartsIn(BaseModel):
    text: str = Field(min_length=1, max_length=500)


class SuggestedPartOut(BaseModel):
    text: str
    word_id: int | None = None
    word: str | None = None
    word_form_id: int | None = None
    word_form_text: str | None = None
    role: str | None = None


class MiniPhraseSettingsOut(BaseModel):
    points_enabled: bool
    points_per_correct: int
    max_per_lesson: int


class MiniPhraseSettingsIn(BaseModel):
    points_enabled: bool | None = None
    points_per_correct: int | None = Field(default=None, ge=0, le=1000)
    max_per_lesson: int | None = Field(default=None, ge=0, le=10)
