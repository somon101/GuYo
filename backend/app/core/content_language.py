"""Which translation language the current request's user reads.

Learners study the dictionary's own language (Russian today) and read its
words and phrases translated into their interface language: Uzbek for an
Uzbek interface, Tajik otherwise (a Russian interface keeps the Tajik
translations it always had). Set once per request from the logged-in user
(app/core/deps.py); admin and anonymous requests keep the Tajik default,
so Admin Web sees exactly what it always did.

With Uzbek or English (English: a Russian-interface choice only) there is no fallback: a word or phrase without an Uzbek
translation is hidden from the pools new content is drawn from. Words
already frozen into a lesson keep a Tajik fallback, so an older lesson
never breaks mid-way.
"""

from contextvars import ContextVar

UI_LANGUAGES = ("ru", "tg", "uz", "en")

# A mutable holder, not the language itself: FastAPI runs sync dependencies
# and endpoints in separate threads, each with its own copy of the context,
# so a plain ContextVar.set() inside get_current_user never reached the
# endpoint. The middleware puts one fresh holder in the request's context
# before both run; they share it and the dependency writes into it.
_language: ContextVar[dict | None] = ContextVar("content_language", default=None)


def begin_request() -> None:
    _language.set({"lang": "tg"})


# What a user may read translations in. Russian is here too: it is a full member
# of the multilingual structure (a concept has a Russian record like any other
# language), and without it "learn English with a Russian hint" -- the most
# obvious pair for a Russian speaker -- would be impossible. Tajik stays the
# fallback when nothing is chosen.
READING_LANGUAGES = ("ru", "tg", "uz", "en")


def reading_language(ui_language: str | None, translation_language: str | None) -> str:
    """A Tajik or Uzbek interface reads its own language; a Russian one
    reads the translation language the user picked."""
    if ui_language in ("tg", "uz"):
        return ui_language
    return translation_language if translation_language in READING_LANGUAGES else "tg"


def set_content_language_for(
    ui_language: str | None,
    translation_language: str | None = None,
    learning_language: str | None = None,
) -> None:
    holder = _language.get()
    if holder is None:
        holder = {}
        _language.set(holder)
    holder["lang"] = reading_language(ui_language, translation_language)
    holder["ui"] = ui_language if ui_language in UI_LANGUAGES else "ru"
    # Язык, который человек изучает. Пусто = язык словаря (так было до
    # многоязычной перестройки, поэтому поведение никого не меняется).
    holder["learn"] = learning_language if learning_language in UI_LANGUAGES else None


def learning_language() -> str | None:
    """Язык, который человек изучает сейчас, или None -- «язык словаря»."""
    holder = _language.get()
    return holder.get("learn") if holder else None


def content_language() -> str:
    holder = _language.get()
    return holder["lang"] if holder else "tg"


def ui_language() -> str:
    """The current request's interface language (ru/tg/uz) -- what
    explanation texts (e.g. mini-phrase templates) are written in."""
    holder = _language.get()
    return holder.get("ui", "ru") if holder else "ru"


def _translation_entries(word) -> list:
    """Переводы слова как языковые записи (многоязычная структура).

    Если записей нет -- структура ещё не перенесена (на бою перенос идёт
    отдельным этапом), и читаем СТАРЫЕ переводы: иначе подсказка пропала бы у
    всех слов сразу. Ровно это и случилось, когда переключение чтения уехало на
    бой раньше данных.

    Запись ИЗУЧАЕМОГО языка в переводах не участвует: она и есть ответ, а
    подсказка должна прийти на другом языке. Изучаемый язык берём из настроек
    человека; если он не выбран -- исключаем свою запись по id (она совпадает с
    id слова), как было до многоязычной перестройки."""
    entries = getattr(word, "language_entries", None) or []
    if not entries:
        return list(getattr(word, "translations", None) or [])
    learn = learning_language()
    if learn is None:
        return [e for e in entries if e.id != word.id]
    return [e for e in entries if e.language != learn]


def primary_translation(word, *, strict: bool = False):
    """The translation to show for `word`, or None. `strict` (used to
    filter pools) never falls back to another language.

    Читается из языковых записей. Порядок выбора ровно тот же, что был у
    старой таблицы переводов: выбранный язык, затем таджикский, затем первая.
    Совпадение со старым путём проверяется `python -m app.word_entries`."""
    entries = _translation_entries(word)
    lang = content_language()
    match = next((t for t in entries if t.language == lang), None)
    if match is not None or strict:
        return match
    tajik = next((t for t in entries if t.language == "tg"), None)
    return tajik or (entries[0] if entries else None)


def has_translation(word) -> bool:
    return primary_translation(word, strict=True) is not None


def only_translated(words: list) -> list:
    """Words readable in the current language; everything under Tajik, as
    before, as long as the word has any translation at all."""
    if content_language() == "tg":
        return words
    return [w for w in words if has_translation(w)]


def phrase_translation(phrase) -> str | None:
    lang = content_language()
    if lang == "uz":
        return phrase.translation_uz
    if lang == "en":
        return phrase.translation_en
    return phrase.translation_tg


def only_translated_phrases(phrases: list) -> list:
    if content_language() == "tg":
        return phrases
    return [p for p in phrases if phrase_translation(p)]
