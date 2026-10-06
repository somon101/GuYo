"""Which translation language the current request's user reads.

Learners study the dictionary's own language (Russian today) and read its
words and phrases translated into their interface language: Uzbek for an
Uzbek interface, Tajik otherwise (a Russian interface keeps the Tajik
translations it always had). Set once per request from the logged-in user
(app/core/deps.py); admin and anonymous requests keep the Tajik default,
so Admin Web sees exactly what it always did.

With Uzbek there is no fallback: a word or phrase without an Uzbek
translation is hidden from the pools new content is drawn from. Words
already frozen into a lesson keep a Tajik fallback, so an older lesson
never breaks mid-way.
"""

from contextvars import ContextVar

UI_LANGUAGES = ("ru", "tg", "uz")

_language: ContextVar[str] = ContextVar("content_language", default="tg")


def set_content_language_for(ui_language: str | None) -> None:
    _language.set("uz" if ui_language == "uz" else "tg")


def content_language() -> str:
    return _language.get()


def primary_translation(word, *, strict: bool = False):
    """The translation row to show for `word`, or None. `strict` (used to
    filter pools) never falls back to another language."""
    lang = content_language()
    match = next((t for t in word.translations if t.language == lang), None)
    if match is not None or strict:
        return match
    tajik = next((t for t in word.translations if t.language == "tg"), None)
    return tajik or (word.translations[0] if word.translations else None)


def has_translation(word) -> bool:
    return primary_translation(word, strict=True) is not None


def only_translated(words: list) -> list:
    """Words readable in the current language; everything under Tajik, as
    before, as long as the word has any translation at all."""
    if content_language() != "uz":
        return words
    return [w for w in words if has_translation(w)]


def phrase_translation(phrase) -> str | None:
    if content_language() == "uz":
        return phrase.translation_uz
    return phrase.translation_tg


def only_translated_phrases(phrases: list) -> list:
    if content_language() != "uz":
        return phrases
    return [p for p in phrases if p.translation_uz]
