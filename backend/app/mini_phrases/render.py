"""Turns a template's explanation text into display segments.

A template is written once per interface language with placeholders, and
explains every phrase that shares its structure:

    {phrase}            the whole mini-phrase ("Я покушал")
    {translation}       its translation in the reader's language
    {parts}             every part in order, joined with " + "
    {1}, {2}, ...       part number N as written in the phrase
    {1.tr}, {2.tr}      the dictionary translation of part N's word
    {pronoun}, {verb}   the first part with that role (see WORD_ROLES)
    {pronoun.tr}, ...   its translation

Unknown placeholders are left as written, so a typo is visible in the
app instead of silently swallowing text. The result is a list of segments
so the app can colour each part by its role.
"""

import re

from app.models.mini_phrase import WORD_ROLES

_PLACEHOLDER = re.compile(r"\{([a-z0-9_]+)(\.tr)?\}")

DEFAULT_EXPLANATIONS = {
    "ru": "Чтобы сказать «{translation}», соедините части по порядку: {parts}. Получается: {phrase}",
    "tg": "Барои гуфтани «{translation}» қисмҳоро бо тартиб пайваст кунед: {parts}. Натиҷа: {phrase}",
    "uz": "«{translation}» deyish uchun qismlarni tartib bilan ulang: {parts}. Natija: {phrase}",
}


def _text(text: str) -> dict:
    return {"kind": "text", "text": text, "role": None}


def render_explanation(template_text: str, phrase_text: str, translation: str, parts: list[dict]) -> list[dict]:
    """`parts` are dicts with `text`, `role`, `translation`, in order."""
    by_role: dict[str, dict] = {}
    for part in parts:
        if part.get("role") and part["role"] not in by_role:
            by_role[part["role"]] = part

    segments: list[dict] = []
    pos = 0
    for match in _PLACEHOLDER.finditer(template_text):
        if match.start() > pos:
            segments.append(_text(template_text[pos : match.start()]))
        pos = match.end()
        key, tr = match.group(1), match.group(2) is not None

        if key == "phrase" and not tr:
            segments.append({"kind": "phrase", "text": phrase_text, "role": None})
        elif key == "translation" and not tr:
            segments.append({"kind": "translation", "text": translation, "role": None})
        elif key == "parts" and not tr:
            for i, part in enumerate(parts):
                if i:
                    segments.append(_text(" + "))
                segments.append({"kind": "part", "text": part["text"], "role": part.get("role")})
        else:
            part = None
            if key.isdigit() and 1 <= int(key) <= len(parts):
                part = parts[int(key) - 1]
            elif key in WORD_ROLES:
                part = by_role.get(key)
            if part is None:
                segments.append(_text(match.group(0)))
            elif tr:
                segments.append({"kind": "translation", "text": part.get("translation") or "", "role": part.get("role")})
            else:
                segments.append({"kind": "part", "text": part["text"], "role": part.get("role")})
    if pos < len(template_text):
        segments.append(_text(template_text[pos:]))
    return [s for s in segments if s["text"]]
