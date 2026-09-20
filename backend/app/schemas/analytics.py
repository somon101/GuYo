from pydantic import BaseModel


class AnalyticsDictionaryOut(BaseModel):
    """One dictionary that actually has phrases -- the only ones worth
    picking in the "Аналитика пользователей" dictionary selector, since a
    dictionary with zero phrases would always show an all-empty report."""

    id: int
    name: str
    language: str
    phrase_count: int


class OpenPhraseAnalyticsOut(BaseModel):
    phrase_id: int
    original: str
    translation_tg: str
    category_name: str | None


class MissingWordOut(BaseModel):
    # None when the phrase contains a token that doesn't match any Word (or
    # its forms) in this dictionary at all -- there is no word to "learn"
    # for it, so `text` is just the raw token as it appears in the phrase.
    word_id: int | None
    text: str


class NearPhraseOut(BaseModel):
    phrase_id: int
    original: str
    translation_tg: str
    category_name: str | None
    learned_count: int
    total_count: int
    missing_words: list[MissingWordOut]


class WordImpactOut(BaseModel):
    word_id: int
    word: str
    new_phrase_count: int
    sample_phrases: list[str]


class UserPhraseAnalyticsOut(BaseModel):
    user_id: int
    user_login: str
    dictionary_id: int
    threshold: int

    learned_word_count: int
    total_word_count: int
    open_phrase_count: int
    total_phrase_count: int
    remaining_phrase_count: int

    open_phrases: list[OpenPhraseAnalyticsOut]
    # Every not-yet-open phrase, sorted by how few words are missing (the
    # ones needing just one more word first) -- Admin Web tiers/paginates
    # this client-side, but the full, already-computed list lives here.
    near_phrases: list[NearPhraseOut]
    # Every not-yet-learned word that is the SOLE missing word for at least
    # one locked phrase, sorted by how many phrases it would immediately
    # complete -- sorted descending by new_phrase_count.
    top_words: list[WordImpactOut]
