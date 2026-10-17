"""Запись мини-фразы на другом языке.

Понятие мини-фразы общее, а языковых записей столько, сколько языков: у каждой
свой текст, свои части и свой шаблон, потому что порядок слов и грамматика у
языков разные. Здесь берутся существующие записи одного языка (обычно словаря)
и к ним добавляются записи другого языка, привязанные к ТОМУ ЖЕ понятию.

Части не выдумываются заново: модель обязана взять слова того языка, на
котором пишет, и указать id понятия, к которому слово относится. Скрипт
проверяет, что написание каждой части действительно есть у этого слова в этом
языке (само слово или его форма) -- тогда упражнение «Собери фразу» соберётся
без расхождений.
"""

from sqlalchemy import func

from app.database import SessionLocal
from app.mini_phrases.generate import (
    PHRASE_LANGUAGE,
    _langs_payload,
    _template_name,
    _template_texts,
    ai_template_explanations,
    chat,
    translation_languages,
)
from app.models.dictionary import Dictionary
from app.models.mini_phrase import (
    MiniPhrase,
    MiniPhraseConcept,
    MiniPhrasePart,
    MiniPhraseTemplate,
    MiniPhraseTemplateTranslation,
)
from app.models.word import Word, WordForm
from app.word_entries import role_for

_TRANSLATE_SYSTEM = (
    "You translate short learning phrases into one target language and mark their parts. Input: "
    "{\"to\":\"target language name\",\"w\":\"id:text,...\" (words of the target language with their concept "
    "id -- the ONLY words you may use),\"p\":[{\"id\":phrase id,\"ru\":\"phrase in another language\","
    "\"parts\":[[concept_id,\"word as written there\"],...]}]}. For each phrase write the SAME meaning in the "
    "target language, 2-5 words, natural and 100% correct, using only words from w (a form of that word is "
    "fine; if the exact form is not in w prefer another wording). Keep the meaning, not the word order: the "
    "target language may order parts differently. p lists EVERY word of your phrase in order as [concept_id, "
    "\"word exactly as written in your phrase\"]. Do not reuse the same content word in two sentences if you "
    "can avoid it. Reply JSON only: {\"r\":[{\"id\":phrase id,\"t\":\"phrase in the target language\","
    "\"p\":[[concept_id,\"word exactly as in t\"],...]}]}."
)


def _language_words(db, dictionary: Dictionary, language: str) -> dict[int, dict]:
    """Слова изучаемого языка: concept_id -> {text, role, forms}.

    Только те понятия, у которых есть запись в этом языке и непустой текст: без
    написания часть фразы собрать нельзя. `forms` -- формы этого языка по
    написанию (в нижнем регистре), чтобы проверить каждую часть фразы.
    """
    result: dict[int, dict] = {}
    words = db.query(Word).filter(Word.dictionary_id == dictionary.id).all()
    for word in words:
        entry = next((e for e in word.language_entries if e.language == language), None)
        text = ((entry.text if entry is not None else "") or "").strip()
        if not text:
            continue
        result[word.id] = {"text": text, "role": role_for(db, word, language), "forms": {}}

    if result:
        forms = (
            db.query(WordForm)
            .filter(WordForm.language == language, WordForm.word_id.in_(list(result)))
            .all()
        )
        for form in forms:
            item = result.get(form.word_id)
            if item is not None:
                item["forms"][form.text.strip().lower()] = form.id
    return result


def _compact(words: dict[int, dict]) -> str:
    return ",".join(f"{word_id}:{item['text'].lower()}" for word_id, item in words.items())


def _source_phrases(db, dictionary: Dictionary, source_language: str, target_language: str, limit: int) -> list[dict]:
    """Фразы исходного языка, у которых ещё нет записи на целевом."""
    existing = (
        db.query(MiniPhrase.concept_id)
        .filter(
            MiniPhrase.dictionary_id == dictionary.id,
            MiniPhrase.language == target_language,
        )
        .all()
    )
    taken = {row[0] for row in existing}
    query = db.query(MiniPhrase).filter(
        MiniPhrase.dictionary_id == dictionary.id,
        MiniPhrase.enabled.is_(True),
        MiniPhrase.language == source_language,
    )
    if taken:
        query = query.filter(MiniPhrase.concept_id.notin_(taken))
    rows = query.order_by(func.random()).limit(limit).all()
    return [
        {
            "id": mp.id,
            "concept_id": mp.concept_id,
            "ru": mp.text,
            "parts": [[p.word_id, p.text] for p in mp.parts],
        }
        for mp in rows
    ]


def preview(db, dictionary: Dictionary, target_language: str, count: int = 10) -> dict:
    """Что будет добавлено на целевом языке. Ничего не сохраняет."""
    if target_language == (dictionary.language or PHRASE_LANGUAGE):
        return {"items": [], "tokens": 0, "reason": "Это язык словаря: его записи уже есть"}
    words = _language_words(db, dictionary, target_language)
    if len(words) < 2:
        return {
            "items": [],
            "tokens": 0,
            "reason": f"На языке «{target_language}» нет слов: сначала наполните словарь",
        }
    sources = _source_phrases(db, dictionary, dictionary.language or PHRASE_LANGUAGE, target_language, count)
    if not sources:
        return {"items": [], "tokens": 0, "reason": "Все фразы уже имеют запись на этом языке"}

    name = next(
        (row[1] for row in _language_names() if row[0] == target_language),
        target_language,
    )
    payload = {
        "to": name,
        "w": _compact(words),
        "p": [{"id": s["id"], "ru": s["ru"], "parts": s["parts"]} for s in sources],
    }
    data, tokens = chat(db, _TRANSLATE_SYSTEM, payload, max_tokens=140 * len(sources) + 400)
    raw = [i for i in data.get("r") or [] if isinstance(i, dict)]

    by_id = {s["id"]: s for s in sources}
    items: list[dict] = []
    for row in raw:
        try:
            source_id = int(row.get("id"))
        except (TypeError, ValueError):
            continue
        source = by_id.get(source_id)
        if source is None:
            continue
        text = str(row.get("t") or "").strip()
        parts = []
        broken = None
        for part in row.get("p") or []:
            if not isinstance(part, (list, tuple)) or len(part) != 2:
                continue
            try:
                word_id = int(part[0])
            except (TypeError, ValueError):
                continue
            written = str(part[1] or "").strip()
            item = words.get(word_id)
            if item is None:
                broken = f"часть «{written}» не из слов этого языка"
                break
            lowered = written.lower()
            if lowered == item["text"].strip().lower():
                parts.append({"word_id": word_id, "text": written, "form_id": None})
            elif lowered in item["forms"]:
                parts.append({"word_id": word_id, "text": written, "form_id": item["forms"][lowered]})
            else:
                broken = f"«{written}» — не слово и не форма слова «{item['text']}»"
                break
        if broken or not text or len(parts) < 2:
            items.append(
                {
                    "source_id": source_id,
                    "source_text": source["ru"],
                    "text": text,
                    "parts": parts,
                    "valid": False,
                    "reason": broken or "меньше двух частей",
                }
            )
            continue
        items.append(
            {
                "source_id": source_id,
                "source_text": source["ru"],
                "concept_id": source["concept_id"],
                "text": text,
                "parts": parts,
                "roles": [words[p["word_id"]]["role"] for p in parts],
                "valid": True,
                "reason": None,
            }
        )
    return {
        "items": items,
        "tokens": tokens,
        "language": target_language,
        "language_name": name,
        "words_sent": len(words),
        "languages": [code for code, _ in translation_languages()],
    }


def _language_names() -> list[tuple[str, str]]:
    from app.models.language import Language

    db = SessionLocal()
    try:
        return [
            (row[0], row[1])
            for row in db.query(Language.code, Language.name).order_by(Language.sort_order).all()
        ]
    finally:
        db.close()


def save(db, dictionary: Dictionary, target_language: str, items: list[dict]) -> dict:
    """Сохраняет выбранные записи. Каждая привязывается к своему понятию."""
    created, skipped = [], []
    new_templates: list[tuple[str, list[str], str]] = []
    for item in items:
        text = str(item.get("text") or "").strip()
        parts = item.get("parts") or []
        roles = [str(r or "other") for r in (item.get("roles") or [])]
        concept_id = item.get("concept_id")
        if not text or not concept_id or len(parts) < 2:
            skipped.append({"text": text, "reason": "нет текста, понятия или частей"})
            continue
        if item.get("valid") is False:
            skipped.append({"text": text, "reason": item.get("reason") or "не прошла проверку"})
            continue
        existing = (
            db.query(MiniPhrase.id)
            .filter(
                MiniPhrase.dictionary_id == dictionary.id,
                MiniPhrase.concept_id == concept_id,
                MiniPhrase.language == target_language,
            )
            .first()
        )
        if existing is not None:
            skipped.append({"text": text, "reason": "такая запись уже есть"})
            continue

        name = _template_name(roles)
        template = (
            db.query(MiniPhraseTemplate)
            .filter(MiniPhraseTemplate.name == name, MiniPhraseTemplate.language == target_language)
            .first()
        )
        if template is None:
            texts = _template_texts(roles) if target_language in ("ru", "tg", "uz") else {}
            template = MiniPhraseTemplate(
                name=name,
                language=target_language,
                distractor_count=2,
                enabled=True,
                **texts,
            )
            db.add(template)
            db.flush()
            for code, value in texts.items():
                if value:
                    db.add(
                        MiniPhraseTemplateTranslation(
                            template_id=template.id,
                            language=code.replace("explanation_", ""),
                            text=value,
                        )
                    )
            new_templates.append((name, roles, texts.get("explanation_ru") or ""))

        mp = MiniPhrase(
            dictionary_id=dictionary.id,
            concept_id=concept_id,
            template_id=template.id,
            language=target_language,
            text=text[:500],
            # Переводы на другие языки у этой записи не нужны: она САМА перевод.
            translation_tg=text[:500],
            translation_uz=None,
            translation_en=None,
            enabled=True,
        )
        db.add(mp)
        db.flush()
        for position, part in enumerate(parts, start=1):
            db.add(
                MiniPhrasePart(
                    mini_phrase_id=mp.id,
                    position=position,
                    text=str(part.get("text") or "")[:255],
                    word_id=int(part["word_id"]),
                    word_form_id=part.get("form_id"),
                )
            )
        created.append(text)

    explain_tokens = 0
    if new_templates:
        langs = [(code, name) for code, name in translation_languages() if code not in ("ru", "tg", "uz")]
        if langs:
            filled, explain_tokens = ai_template_explanations(db, new_templates, langs)
            for name, _roles, _reference in new_templates:
                template = (
                    db.query(MiniPhraseTemplate)
                    .filter(
                        MiniPhraseTemplate.name == name,
                        MiniPhraseTemplate.language == target_language,
                    )
                    .first()
                )
                if template is None:
                    continue
                for code, value in (filled.get(name) or {}).items():
                    db.add(
                        MiniPhraseTemplateTranslation(
                            template_id=template.id, language=code, text=value
                        )
                    )
    db.commit()
    return {"created": created, "skipped": skipped, "tokens": explain_tokens}
