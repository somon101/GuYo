"""Языки платформы: то, что админка показывает и правит."""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class LanguageOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    code: str
    name: str
    native_name: str | None
    alphabet: str | None
    is_enabled: bool
    sort_order: int


class LanguageIn(BaseModel):
    """Новый язык. Заводится одной строкой, без слов.

    Слова -- это языковые записи понятий: их наполняют потом (вручную в карточке
    понятия, импортом или ИИ-генератором). Так язык перестал быть тем, что можно
    добавить только правкой кода."""

    code: str = Field(min_length=2, max_length=3)
    name: str = Field(min_length=1, max_length=64)
    native_name: str | None = Field(default=None, max_length=64)
    alphabet: str | None = Field(default=None, max_length=256)


class LanguagePatch(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=64)
    native_name: str | None = Field(default=None, max_length=64)
    alphabet: str | None = Field(default=None, max_length=256)
    is_enabled: bool | None = None
    sort_order: int | None = None


class LanguageDetail(LanguageOut):
    """Язык вместе с тем, чем он наполнен: понятно, что ещё нужно сделать."""

    entries: int
    with_audio: int
    with_transcription: int
    forms: int
    phrase_entries: int
    created_at: datetime
