"""Allowed language codes for word translations / pronunciation audio.

Deliberately a plain list validated in the API layer, not a database enum:
adding a new language (e.g. Tajik) later is then a one-line change here plus
a code deploy, with no migration needed -- word_translations.language is a
plain string column.

Dictionary.language (English / Russian / Chinese) is a separate, stricter
enum on purpose: that one is a hard product constraint for this stage
("only three dictionary languages"). Translation languages are not -- a
word can pick up a translation in any supported language independent of
how many dictionaries exist for it.
"""

TRANSLATION_LANGUAGE_LABELS: dict[str, str] = {
    "en": "English",
    "ru": "Русский",
    "zh": "中文",
    "tg": "Тоҷикӣ",
}

ALLOWED_TRANSLATION_LANGUAGES = set(TRANSLATION_LANGUAGE_LABELS)


def is_valid_translation_language(code: str) -> bool:
    return code in ALLOWED_TRANSLATION_LANGUAGES
