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
    # Интерфейс приложения на этом языке переведён: только такие языки
    # предлагаются в переключателе интерфейса.
    ui_ready: bool
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
    ui_ready: bool | None = None
    sort_order: int | None = None


class LanguageDetail(LanguageOut):
    """Язык вместе с тем, чем он наполнен: понятно, что ещё нужно сделать."""

    entries: int
    with_audio: int
    with_transcription: int
    forms: int
    phrase_entries: int
    created_at: datetime


class LanguageFormOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    text: str


class LanguageWordDetail(BaseModel):
    """Слово одного языка так, как его правит админка.

    Языковые поля (написание, транскрипция, аудио, формы) принадлежат ЭТОМУ
    языку и правятся здесь. Классификация (роль, важность, категория, темы,
    картинка) принадлежит понятию и правится в разделе «База» -- дублировать её
    по языкам незачем, связь идёт через concept_id."""

    id: int
    concept_id: int
    language: str
    text: str
    transcription: str | None
    audio_url: str | None
    forms: list[LanguageFormOut]
    # Общее у понятия -- только для показа и перехода в «Базу».
    dictionary_id: int
    role: str | None
    importance: int
    category_id: int | None
    # Как это же понятие выглядит на других языках: полезно видеть рядом.
    siblings: list[dict]


class LanguageWordPatch(BaseModel):
    text: str | None = Field(default=None, min_length=1, max_length=255)
    transcription: str | None = Field(default=None, max_length=255)
    remove_transcription: bool = False


class LanguageFormIn(BaseModel):
    text: str = Field(min_length=1, max_length=255)
