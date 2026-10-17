"""Заполнение пробелов языка: формы слов и транскрипции.

У узбекского и английского нет ни одной формы, у таджикского не хватает части —
из-за этого упражнение «Собери слово» и мини-фразы на этих языках не собираются.
Здесь пробелы закрываются моделью: она получает слово НА ЭТОМ языке и возвращает
его формы и транскрипцию. Русские формы при этом не трогаются, а всё, что
приходит, проверяется скриптом (написание, дубликаты, длина).

Озвучка сюда не входит: в проекте нет синтеза речи, файлы только загружаются.
"""

from sqlalchemy import func

from app.mini_phrases.generate import chat
from app.models.concept import WordEntry, WordEntryForm
from app.models.language import Language
from app.models.word import Word, WordForm

_PER_REQUEST = 20

_FORMS_SYSTEM = (
    "You fill in missing data for dictionary words of one language. Input: {\"lang\":\"language name\","
    "\"w\":[{\"id\":word id,\"t\":\"word in that language\"}]}. For each word return its transcription and its "
    "common grammatical forms IN THAT LANGUAGE, exactly as a learner meets them in real sentences. "
    "Forms: for languages with case/verb endings give the usual set (verbs -- present/future, past, "
    "imperative; nouns -- plural and cases if the language has them; adjectives -- gender/number/cases); "
    "for languages without inflection (e.g. Chinese) return an empty list -- never invent forms. "
    "Lowercase, no duplicates, never repeat the word itself. Transcription: Latin letters, only if the "
    "language is written in a non-Latin script (Chinese -- pinyin with tones), otherwise empty. "
    "Reply JSON only: {\"r\":[{\"id\":word id,\"tr\":\"transcription or empty\",\"f\":[\"form\",...]}]}."
)


def _language_name(db, code: str) -> str:
    row = db.get(Language, code)
    return (row.name if row is not None else None) or code


def plan(db, language: str) -> dict:
    """Что именно не заполнено у языка: сколько слов без форм и без транскрипции."""
    total = db.query(func.count(WordEntry.id)).filter(WordEntry.language == language).scalar() or 0
    with_forms = (
        db.query(func.count(func.distinct(WordEntryForm.word_entry_id)))
        .join(WordEntry, WordEntry.id == WordEntryForm.word_entry_id)
        .filter(WordEntry.language == language)
        .scalar()
        or 0
    )
    with_transcription = (
        db.query(func.count(WordEntry.id))
        .filter(WordEntry.language == language, WordEntry.transcription.isnot(None))
        .scalar()
        or 0
    )
    return {
        "language": language,
        "name": _language_name(db, language),
        "words": int(total),
        "with_forms": int(with_forms),
        "with_transcription": int(with_transcription),
        "missing_forms": int(total) - int(with_forms),
        "missing_transcription": int(total) - int(with_transcription),
    }


def _candidates(db, language: str, limit: int) -> list[WordEntry]:
    """Записи без форм или без транскрипции, по одной на понятие.

    Берём с непустым текстом: без написания формы не собрать."""
    has_forms = (
        db.query(WordEntryForm.word_entry_id)
        .filter(WordEntryForm.word_entry_id == WordEntry.id)
        .exists()
    )
    return (
        db.query(WordEntry)
        .filter(
            WordEntry.language == language,
            func.coalesce(WordEntry.text, "") != "",
            (WordEntry.transcription.is_(None)) | (~has_forms),
        )
        .order_by(WordEntry.id)
        .limit(limit)
        .all()
    )


def preview(db, language: str, limit: int = _PER_REQUEST) -> dict:
    """Что модель предложит: формы и транскрипция. Ничего не сохраняет."""
    entries = _candidates(db, language, limit)
    if not entries:
        return {"items": [], "tokens": 0, "reason": "У всех слов этого языка уже есть формы и транскрипция"}
    payload = {
        "lang": _language_name(db, language),
        "w": [{"id": e.id, "t": e.text} for e in entries],
    }
    data, tokens = chat(db, _FORMS_SYSTEM, payload, max_tokens=120 * len(entries) + 300)
    by_id = {e.id: e for e in entries}
    # Уже существующие формы: не предлагаем их повторно.
    existing = {
        (row.word_entry_id, row.text.strip().lower())
        for row in db.query(WordEntryForm)
        .filter(WordEntryForm.word_entry_id.in_(list(by_id)))
        .all()
    }
    items = []
    for row in data.get("r") or []:
        if not isinstance(row, dict):
            continue
        try:
            entry_id = int(row.get("id"))
        except (TypeError, ValueError):
            continue
        entry = by_id.get(entry_id)
        if entry is None:
            continue
        transcription = str(row.get("tr") or "").strip()[:255]
        forms = []
        for value in row.get("f") or []:
            form = str(value or "").strip()[:255]
            if not form or form.lower() == entry.text.strip().lower():
                continue
            if (entry_id, form.lower()) in existing:
                continue
            if form in forms:
                continue
            forms.append(form)
        items.append(
            {
                "entry_id": entry_id,
                "word": entry.text,
                "transcription": transcription,
                "forms": forms,
                "has_transcription": entry.transcription is not None,
            }
        )
    return {"items": items, "tokens": tokens, "language": language}


def save(db, language: str, items: list[dict]) -> dict:
    """Сохраняет формы и транскрипции в языковые записи (и в старые таблицы)."""
    forms_added = 0
    transcriptions = 0
    skipped = []
    for item in items:
        try:
            entry_id = int(item.get("entry_id"))
        except (TypeError, ValueError):
            continue
        entry = db.get(WordEntry, entry_id)
        if entry is None or entry.language != language:
            skipped.append({"entry_id": entry_id, "reason": "запись не найдена"})
            continue
        transcription = str(item.get("transcription") or "").strip()
        if transcription and not entry.transcription:
            entry.transcription = transcription[:255]
            transcriptions += 1
        for value in item.get("forms") or []:
            form = str(value or "").strip()[:255]
            if not form or form.lower() == (entry.text or "").strip().lower():
                continue
            same = (
                db.query(WordEntryForm)
                .filter(
                    WordEntryForm.word_entry_id == entry.id,
                    func.lower(WordEntryForm.text) == form.lower(),
                )
                .first()
            )
            if same is not None:
                continue
            row = WordEntryForm(word_entry_id=entry.id, language=language, text=form)
            db.add(row)
            db.flush()
            # Зеркало в старую таблицу форм: на неё ссылаются части мини-фраз и
            # админская карточка понятия. id совпадает, как и при переносе;
            # если он занят -- пропускаем зеркало, данные важнее.
            word = db.get(Word, entry.concept_id)
            if word is not None and db.get(WordForm, row.id) is None:
                db.add(WordForm(id=row.id, word_id=word.id, language=language, text=form))
            forms_added += 1
    db.commit()
    return {"forms_added": forms_added, "transcriptions": transcriptions, "skipped": skipped}
