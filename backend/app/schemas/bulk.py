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
