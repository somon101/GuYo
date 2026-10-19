"""Мини-фразы, написанные сразу на изучаемом языке.

У каждого языка свои мини-фразы и свои шаблоны: фраза не переводится с
русского, а составляется на своём языке по его грамматике. Механизм тот же:
каждая часть -- слово этого языка из общего словаря (номер понятия), или его
форма; шаблон объясняет фразу на языке, который человек читает.

Два пути, оба внутри выбранного языка:

* **генерация** -- модель получает только слова этого языка и пишет новые
  фразы; скрипт проверяет каждую часть по словарю этого языка;
* **вручную** -- админ пишет фразу, скрипт разбирает её на слова этого языка
  (или говорит, какого слова нет), модель подбирает шаблон этого языка или
  предлагает новый, и пишет подсказки-переводы.

Подсказки и объяснения пишутся на все языки из таблицы languages.
"""

import re

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.mini_phrases.generate import (
    _langs_payload,
    _template_name,
    _template_texts,
    ai_template_explanations,
    chat,
)
from app.mini_phrases.service import normalize_answer
from app.mini_phrases.texts import set_explanations, set_translations
from app.mini_phrases.translate_phrases import _compact, _language_words
from app.models.dictionary import Dictionary
from app.models.language import Language
from app.models.mini_phrase import (
    MiniPhrase,
    MiniPhraseConcept,
    MiniPhrasePart,
    MiniPhraseTemplate,
)

_TOKEN = re.compile(r"[^\W\d_]+(?:[-'’][^\W\d_]+)*", re.UNICODE)


def reading_languages(db: Session, language: str) -> list[tuple[str, str]]:
    """Языки подсказок для фраз языка `language`: все включённые, кроме него."""
    rows = (
        db.query(Language.code, Language.name)
        .filter(Language.is_enabled.is_(True))
        .order_by(Language.sort_order, Language.code)
        .all()
    )
    return [(code, name) for code, name in rows if code != language]


def _language_name(db: Session, language: str) -> str:
    row = db.get(Language, language)
    return row.name if row is not None else language


def _existing_texts(db: Session, dictionary_id: int, language: str) -> set[str]:
    return {
        normalize_answer(t)
        for (t,) in db.query(MiniPhrase.text).filter(
            MiniPhrase.dictionary_id == dictionary_id, MiniPhrase.language == language
        )
    }


def _check_parts(words: dict[int, dict], raw_parts) -> tuple[list[dict], str | None]:
    """[[concept_id, "как написано"], ...] -> части, или причина отказа."""
    parts = []
    for part in raw_parts or []:
        if not isinstance(part, (list, tuple)) or len(part) != 2:
            continue
        try:
            word_id = int(part[0])
        except (TypeError, ValueError):
            return parts, "неверный номер слова"
        written = str(part[1] or "").strip()
        item = words.get(word_id)
        if item is None:
            return parts, f"«{written}» — не слово этого языка"
        lowered = written.lower()
        if lowered == item["text"].strip().lower():
            parts.append({"word_id": word_id, "text": written, "form_id": None, "role": item["role"]})
        elif lowered in item["forms"]:
            parts.append({"word_id": word_id, "text": written, "form_id": item["forms"][lowered], "role": item["role"]})
        else:
            return parts, f"«{written}» — не слово и не форма слова «{item['text']}»"
    return parts, None


def _templates_of(db: Session, language: str) -> list[MiniPhraseTemplate]:
    return (
        db.query(MiniPhraseTemplate)
        .filter(MiniPhraseTemplate.language == language, MiniPhraseTemplate.enabled.is_(True))
        .order_by(MiniPhraseTemplate.id)
        .all()
    )


def _clean_hints(raw, allowed: set[str]) -> dict[str, str]:
    if not isinstance(raw, dict):
        return {}
    return {
        str(code).strip().lower(): str(text).strip()
        for code, text in raw.items()
        if str(code).strip().lower() in allowed and str(text or "").strip()
    }


# --- Генерация ------------------------------------------------------------------

_GENERATE_SYSTEM = (
    "You are an experienced teacher of {lang}. Your learners are adult beginners who need {lang} to COMMUNICATE. "
    "Input: {\"n\":how many,\"topic\":\"topic or empty\",\"w\":\"id:word,...\" (words of {lang} with their "
    "concept id -- the ONLY words you may use; a grammatical form of such a word is fine),\"have\":[phrases the "
    "learner already has],\"langs\":\"code:name,...\"}. Write n NEW short phrases (2-5 words) that people really "
    "say in {lang} in everyday conversation: questions, requests, answers, politeness, needs, wishes, plans, "
    "feelings. Every phrase must be 100% correct, natural {lang} -- written by a native speaker, NOT a "
    "word-for-word translation from another language. Every word of a phrase must be a word of w or its form; "
    "if a phrase needs a word that is not in w, choose another phrase. Do not repeat the meaning of have or of "
    "your other phrases; use many different words. For every phrase give a short natural hint (translation) in "
    "EVERY language of langs. Reply JSON only: {\"r\":[{\"t\":\"phrase\",\"p\":[[concept_id,\"word exactly as in "
    "t\"],...],\"tr\":{\"<code>\":\"hint\"}}]}. p lists every word of t in order."
)


def generate_preview(db: Session, dictionary: Dictionary, language: str, count: int, topic: str = "") -> dict:
    """Новые фразы на языке `language`. Ничего не сохраняет."""
    words = _language_words(db, dictionary, language)
    if len(words) < 2:
        return {"items": [], "tokens": 0, "reason": "На этом языке нет слов: сначала наполните словарь"}
    lang_name = _language_name(db, language)
    hints = reading_languages(db, language)
    have = sorted(_existing_texts(db, dictionary.id, language))
    system = _GENERATE_SYSTEM.replace("{lang}", lang_name)
    data, tokens = chat(
        db,
        system,
        {"n": count, "topic": topic, "w": _compact(words), "have": have[-150:], "langs": _langs_payload(hints)},
        max_tokens=(160 + 50 * len(hints)) * count + 500,
    )
    allowed = {code for code, _ in hints}
    templates = {t.name for t in _templates_of(db, language)}
    existing = set(have)
    seen: set[str] = set()
    items = []
    for row in data.get("r") or []:
        if not isinstance(row, dict):
            continue
        text = str(row.get("t") or "").strip()
        parts, reason = _check_parts(words, row.get("p"))
        if not reason and normalize_answer(" ".join(p["text"] for p in parts)) != normalize_answer(text):
            reason = "части не совпадают с фразой"
        if not reason and len(parts) < 2:
            reason = "меньше двух частей"
        key = normalize_answer(text)
        if not reason and (key in existing or key in seen):
            reason = "такая мини-фраза уже есть"
        seen.add(key)
        roles = [p["role"] or "other" for p in parts]
        name = _template_name(roles) if parts else ""
        items.append(
            {
                "text": text,
                "parts": parts,
                "roles": roles,
                "translations": _clean_hints(row.get("tr"), allowed),
                "template_name": name,
                "template_exists": name in templates,
                "valid": reason is None,
                "reason": reason,
            }
        )
    return {"items": items, "tokens": tokens, "language": language, "words_sent": len(words)}


# --- Вручную ----------------------------------------------------------------------


def manual_check(db: Session, dictionary: Dictionary, language: str, text: str) -> dict:
    """Разбирает фразу на слова этого языка. Каждое слово ищется среди слов
    языка и их форм; чего нет -- перечисляется, и фраза не принимается."""
    words = _language_words(db, dictionary, language)
    by_text: dict[str, tuple[int, int | None]] = {}
    for word_id, item in words.items():
        by_text.setdefault(item["text"].strip().lower(), (word_id, None))
    for word_id, item in words.items():
        for form, form_id in item["forms"].items():
            by_text.setdefault(form, (word_id, form_id))
    parts, missing = [], []
    for token in _TOKEN.findall(text):
        hit = by_text.get(token.lower())
        if hit is None:
            missing.append(token)
            continue
        word_id, form_id = hit
        parts.append(
            {
                "word_id": word_id,
                "text": token,
                "form_id": form_id,
                "role": words[word_id]["role"] or "other",
                "base": words[word_id]["text"],
            }
        )
    duplicate = normalize_answer(text) in _existing_texts(db, dictionary.id, language)
    return {
        "text": text.strip(),
        "parts": parts,
        "missing": missing,
        "duplicate": duplicate,
        "ok": not missing and len(parts) >= 1 and not duplicate,
    }


_TEMPLATE_SYSTEM = (
    "You organise short learning phrases of {lang} into templates (groups of phrases with the same structure, "
    "explained by one instruction). Input: {\"phrase\":\"...\",\"parts\":[[\"word\",\"role\"],...],"
    "\"templates\":[{\"id\":1,\"name\":\"...\",\"example\":\"a phrase of it or empty\"}],\"langs\":\"code:name,...\"}. "
    "If one of templates has the SAME structure as the phrase (same kinds of parts in the same order), answer its "
    "id. Otherwise answer id null. Also write a short natural hint (translation) of the phrase in EVERY language "
    "of langs. Reply JSON only: {\"id\":template id or null,\"why\":\"one short sentence in Russian\","
    "\"tr\":{\"<code>\":\"hint\"}}."
)


def manual_template(db: Session, dictionary: Dictionary, language: str, text: str, parts: list[dict]) -> dict:
    """Шаблон для ручной фразы: подходящий из шаблонов ЭТОГО языка, или новый
    (с объяснениями на все языки), плюс подсказки-переводы. Ничего не сохраняет."""
    roles = [str(p.get("role") or "other") for p in parts]
    hints = reading_languages(db, language)
    templates = _templates_of(db, language)
    examples = {}
    for t in templates:
        mp = db.query(MiniPhrase.text).filter(MiniPhrase.template_id == t.id).first()
        examples[t.id] = mp[0] if mp else ""
    payload = {
        "phrase": text,
        "parts": [[p.get("text"), r] for p, r in zip(parts, roles)],
        "templates": [{"id": t.id, "name": t.name, "example": examples[t.id]} for t in templates],
        "langs": _langs_payload(hints),
    }
    system = _TEMPLATE_SYSTEM.replace("{lang}", _language_name(db, language))
    try:
        data, tokens = chat(db, system, payload, max_tokens=400 + 60 * len(hints))
    except HTTPException:
        data, tokens = {}, 0
    chosen = None
    try:
        wanted = int(data.get("id")) if data.get("id") is not None else None
    except (TypeError, ValueError):
        wanted = None
    chosen = next((t for t in templates if t.id == wanted), None)
    name = _template_name(roles)
    if chosen is None:
        # The model found nothing that fits (or did not answer): the template
        # named after the parts' roles, if this language already has it.
        chosen = next((t for t in templates if t.name == name), None)
    out = {
        "translations": _clean_hints(data.get("tr"), {code for code, _ in hints}),
        "why": str(data.get("why") or "").strip(),
        "tokens": tokens,
        "roles": roles,
    }
    if chosen is not None:
        out["template"] = {"id": chosen.id, "name": chosen.name, "new": False}
        return out
    explanations = _new_template_explanations(db, name, roles, hints)
    out["template"] = {"id": None, "name": name, "new": True, "explanations": explanations}
    return out


def _new_template_explanations(db: Session, name: str, roles: list[str], hints: list[tuple[str, str]]) -> dict:
    texts = {k.replace("explanation_", ""): v for k, v in _template_texts(roles).items() if v}
    rest = [(code, lang) for code, lang in hints + [("ru", "Русский")] if code not in texts]
    if rest:
        filled, _ = ai_template_explanations(db, [(name, roles, texts.get("ru", ""))], rest)
        texts.update(filled.get(name) or {})
    return texts


# --- Сохранение -----------------------------------------------------------------


def save(db: Session, dictionary: Dictionary, language: str, items: list[dict]) -> dict:
    """Сохраняет фразы языка `language` (из генерации или вручную). Каждая --
    новое понятие со своей записью; шаблон -- выбранный, или новый этого языка."""
    words = _language_words(db, dictionary, language)
    existing = _existing_texts(db, dictionary.id, language)
    hints = reading_languages(db, language)
    created, skipped = [], []
    for item in items:
        text = str(item.get("text") or "").strip()
        parts, reason = _check_parts(words, [[p.get("word_id"), p.get("text")] for p in item.get("parts") or []])
        if not reason and normalize_answer(" ".join(p["text"] for p in parts)) != normalize_answer(text):
            reason = "части не совпадают с фразой"
        if not reason and not parts:
            reason = "нет частей"
        if not reason and normalize_answer(text) in existing:
            reason = "такая мини-фраза уже есть"
        if reason:
            skipped.append({"text": text, "reason": reason})
            continue
        roles = [p["role"] or "other" for p in parts]
        template = None
        template_id = item.get("template_id")
        if template_id:
            template = db.get(MiniPhraseTemplate, int(template_id))
            if template is not None and template.language != language:
                template = None  # a template of another language never applies here
        if template is None:
            name = str(item.get("template_name") or "").strip() or _template_name(roles)
            template = (
                db.query(MiniPhraseTemplate)
                .filter(MiniPhraseTemplate.name == name, MiniPhraseTemplate.language == language)
                .first()
            )
            if template is None:
                template = MiniPhraseTemplate(name=name, language=language, distractor_count=2, enabled=True)
                db.add(template)
                db.flush()
                explanations = item.get("explanations") or _new_template_explanations(db, name, roles, hints)
                set_explanations(db, template, explanations)
        concept = MiniPhraseConcept(dictionary_id=dictionary.id)
        db.add(concept)
        db.flush()
        mp = MiniPhrase(
            dictionary_id=dictionary.id,
            concept_id=concept.id,
            template_id=template.id,
            language=language,
            text=text[:500],
            translation_tg="",
            enabled=True,
        )
        db.add(mp)
        db.flush()
        set_translations(db, mp, item.get("translations") or {})
        for position, part in enumerate(parts, start=1):
            db.add(
                MiniPhrasePart(
                    mini_phrase_id=mp.id,
                    position=position,
                    text=part["text"][:255],
                    word_id=part["word_id"],
                    word_form_id=part["form_id"],
                )
            )
        existing.add(normalize_answer(text))
        created.append(text)
    db.commit()
    return {"created": created, "skipped": skipped}
