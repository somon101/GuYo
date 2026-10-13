"""Wire shapes of «Проверка текста» (app/text_check/).

Field names are the ones the prototype's own API used (and the Flutter screen
parses), so the client model is a direct mirror of this file:

    {ok, summary, errors[{group, fragment, correct, explanation}], corrected_text}

Three fields are added to that answer so the app never needs a second call to
keep its counter honest: how this check was produced (`cached`) and what is
left today (`remaining`, `daily_limit`, `unlimited`).
"""

from typing import Literal

from pydantic import BaseModel, Field

# The hard ceiling a request may ever carry -- the cache/journal column size.
# The REAL limit is the admin's own `max_chars` (app/models/text_check.py),
# applied in the router so it can change without a new app build.
MAX_TEXT_LENGTH = 2000

# GuYo's own language codes. Note "tg" for Tajik (the prototype wrote "tj",
# which this project never uses); "en" is the explanation language only --
# the checked text is always Russian.
ExplanationLanguage = Literal["ru", "tg", "uz", "en"]


class CheckRequest(BaseModel):
    text: str = Field(min_length=1, max_length=MAX_TEXT_LENGTH)
    # "Я" and "собеседник" decide which verb endings and address forms are
    # correct; the addressee may be unknown (the app's default), in which
    # case the model is told not to punish either form.
    user_gender: Literal["male", "female"]
    addressee_gender: Literal["male", "female", "unknown"] = "unknown"
    # One on/off switch, not a three-way choice: "formal" checks that the
    # message stays formal, null means formality is not checked at all.
    # ("informal" is still accepted -- the checker has always known how to
    # enforce it -- but the app never sends it.)
    formality: Literal["formal", "informal"] | None = None
    check_punctuation: bool = True
    explanation_language: ExplanationLanguage = "ru"


class CheckErrorOut(BaseModel):
    """One mistake: the fragment as written, what it should be, and why.
    `group` is one of the keys in app/text_check/deepseek.py's ERROR_GROUPS;
    the app turns it into its own localized title."""

    group: str
    fragment: str
    correct: str
    explanation: str


class CheckResultOut(BaseModel):
    ok: bool
    summary: str
    errors: list[CheckErrorOut]
    corrected_text: str

    # True when this answer came from the cache: it cost nothing, so it did
    # NOT count against the daily limit -- and the app says so, otherwise a
    # counter that refuses to move looks like a bug.
    cached: bool = False
    # Checks left today, or None when no limit applies.
    remaining: int | None = None
    daily_limit: int | None = None
    unlimited: bool = False


class CheckInfoOut(BaseModel):
    """What the screen needs before the first message is typed: whether the
    checker is on, how long a message may be, and how many checks are left."""

    enabled: bool
    max_chars: int
    remaining: int | None
    daily_limit: int | None
    unlimited: bool
