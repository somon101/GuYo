"""Wire shapes of «Проверка текста» (app/text_check/deepseek.py).

Field names are the ones the prototype's own API used (and the Flutter screen
parses), so the client model is a direct mirror of this file:

    {ok, summary, errors[{group, fragment, correct, explanation}], corrected_text}
"""

from typing import Literal

from pydantic import BaseModel, Field

# The same limit the prototype's textarea has -- one message, not an essay.
MAX_TEXT_LENGTH = 500

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
