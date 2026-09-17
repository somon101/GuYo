from pydantic import BaseModel, Field


class ImportWord(BaseModel):
    word: str = Field(min_length=1, max_length=255)
    # Not every existing word has a Tajik translation yet, so this is
    # allowed to be empty (both on import and on export) rather than
    # required -- a hard requirement here would make export crash on data
    # that predates this format.
    translation_tg: str = Field(default="", max_length=255)
    forms: list[str] = Field(default_factory=list)
    forms_tg: list[str] = Field(default_factory=list)
    # Paths (relative to the dictionary ZIP root, e.g.
    # "audio/original/<file>.mp3") to this word's own pronunciation and to
    # its Tajik translation's pronunciation -- never language-suffixed
    # (no audio_ru/audio_en/...): `audio` always means "pronunciation in
    # this dictionary's own language", whatever that language is. Optional
    # since not every word has recorded audio.
    audio: str | None = Field(default=None, max_length=512)
    audio_tg: str | None = Field(default=None, max_length=512)


class ImportCategory(BaseModel):
    name: str = Field(min_length=1, max_length=128)
    words: list[ImportWord] = Field(default_factory=list)


class ImportPayload(BaseModel):
    categories: list[ImportCategory] = Field(default_factory=list)


class ImportSummary(BaseModel):
    categories_created: int
    categories_reused: int
    words_created: int
    words_reused: int
    forms_added: int


# Export uses the exact same shape as import, so a re-exported file can be
# fed straight back into import with no conversion.
ExportWord = ImportWord
ExportCategory = ImportCategory


class ExportPayload(BaseModel):
    categories: list[ExportCategory] = Field(default_factory=list)


# --- Phrases -------------------------------------------------------------
# Same import/export principle as Words above, but Phrase has no forms and
# always carries its Tajik translation directly (translation_tg is a
# required, non-null column on Phrase itself, not an optional child row),
# so it's required here too -- unlike ImportWord.translation_tg.


class ImportPhrase(BaseModel):
    sentence: str = Field(min_length=1, max_length=1000)
    translation_tg: str = Field(min_length=1, max_length=1000)


class ImportPhraseCategory(BaseModel):
    name: str = Field(min_length=1, max_length=128)
    phrases: list[ImportPhrase] = Field(default_factory=list)


class ImportPhrasePayload(BaseModel):
    categories: list[ImportPhraseCategory] = Field(default_factory=list)


class ImportPhraseSummary(BaseModel):
    categories_created: int
    categories_reused: int
    phrases_created: int
    phrases_reused: int


ExportPhrase = ImportPhrase
ExportPhraseCategory = ImportPhraseCategory


class ExportPhrasePayload(BaseModel):
    categories: list[ExportPhraseCategory] = Field(default_factory=list)
