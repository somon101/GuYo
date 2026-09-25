from datetime import datetime

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


class WordLevelSummaryOut(BaseModel):
    """The level a score currently falls in -- None when no enabled
    WordLevel's range covers it (a gap in the ladder, or none configured
    at all), rather than guessing a nearest level."""

    id: int
    name: str
    min_points: int
    max_points: int | None


class UserWordProgressOut(BaseModel):
    """One row of the word-picker list on a user's diagnostics page --
    every Word this user has EVER attempted (has a WordProgress row for),
    in this dictionary, regardless of current level."""

    word_id: int
    word: str
    translation: str | None
    dictionary_id: int
    score: int
    level: WordLevelSummaryOut | None
    total_attempts: int
    updated_at: datetime


class ExerciseAttemptStatsOut(BaseModel):
    """This user's lifetime record for one word, narrowed to one exercise
    type -- computed by grouping WordAttempt, never a second stored
    counter."""

    exercise_key: str
    total_attempts: int
    total_correct: int
    total_errors: int


class WordAttemptOut(BaseModel):
    """One row of WordAttempt, as-is -- the full, unfiltered history for
    one (user, word). See app/models/word_attempt.py for what score_after
    actually means."""

    exercise_key: str
    is_correct: bool
    score_after: int
    created_at: datetime


class PriorityBandSummaryOut(BaseModel):
    id: int
    name: str


class WordDiagnosticsOut(BaseModel):
    """Everything Admin Web's «Диагностика слова» block needs for one
    (user, word) pair, already aggregated server-side -- Admin Web only
    renders this, it never computes a total/average/breakdown itself (see
    app/routers/admin_analytics.py's own module docstring)."""

    user_id: int
    user_login: str

    word_id: int
    word: str
    translation: str | None

    score: int
    level: WordLevelSummaryOut | None

    total_attempts: int
    total_correct: int
    total_errors: int

    # Priority -- an analytics layer on top of everything above (see
    # app/priority/), computed fresh on every read, never stored.
    priority_score: float
    priority_level: PriorityBandSummaryOut | None
    stability_percent: int | None
    stability_level: PriorityBandSummaryOut | None
    days_since_last_attempt: int | None

    # One entry per exercise_key that has EVER been attempted for this
    # word -- an exercise never attempted simply doesn't appear, rather
    # than showing a padded 0/0/0 row for every possible type.
    by_exercise: list[ExerciseAttemptStatsOut]

    last_attempt: WordAttemptOut | None
    # Oldest first -- a time-series chart reads this left-to-right as-is,
    # with no client-side sort.
    history: list[WordAttemptOut]
