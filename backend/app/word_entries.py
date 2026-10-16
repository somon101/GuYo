"""Чтение из новой структуры и доказательство, что оно совпадает со старым.

Этап 3 плана (docs/multilingual-migration.md). Прежде чем переключать упражнения,
уроки и приоритет на языковые записи, надо доказать, что новый путь чтения даёт
РОВНО то же, что старый, — иначе переключение будет вслепую.

Здесь оба пути:

* **резолверы новой модели** — как понятие читается на нужном языке;
* **сравнение** (`compare_reads`) — проходит по всем словам и всем языкам чтения
  и показывает любое расхождение.

Совпадение старого и нового обязательно: миграция переносила данные один в один,
и проверка это подтверждает (или ловит ошибку переноса).

Запуск: `python -m app.word_entries`
"""

from __future__ import annotations

import sys
from collections import defaultdict

from sqlalchemy.orm import Session

from app.core.content_language import content_language, set_content_language_for
from app.database import SessionLocal
from app.models.concept import WordEntry, WordEntryForm
from app.models.dictionary import Dictionary
from app.models.word import Word

# Языки чтения: те, что человек может выбрать родным (см. core/languages.py).
READING_LANGUAGES = ("tg", "uz", "en")


def entries_by_concept(db: Session, concept_ids: list[int]) -> dict[int, list[WordEntry]]:
    """Все языковые записи этих понятий, одним запросом (без N+1)."""
    if not concept_ids:
        return {}
    rows = (
        db.query(WordEntry)
        .filter(WordEntry.concept_id.in_(concept_ids))
        .order_by(WordEntry.concept_id, WordEntry.id)
        .all()
    )
    grouped: dict[int, list[WordEntry]] = defaultdict(list)
    for row in rows:
        grouped[row.concept_id].append(row)
    return grouped


def learning_entry(entries: list[WordEntry], dictionary_language: str) -> WordEntry | None:
    """Запись ИЗУЧАЕМОГО языка — то, что человек учит и произносит."""
    return next((e for e in entries if e.language == dictionary_language), None)


def native_entry(entries: list[WordEntry], language: str) -> WordEntry | None:
    """Запись РОДНОГО языка — подсказка.

    Ровно тот же порядок, что у старого `primary_translation`: выбранный язык, при
    отсутствии — таджикский (как раньше), при отсутствии — первая запись другого
    языка. Порядок обязан совпадать, иначе после переключения люди увидят другие
    подсказки."""
    if language != "ru":
        match = next((e for e in entries if e.language == language), None)
        if match is not None:
            return match
    tajik = next((e for e in entries if e.language == "tg"), None)
    if tajik is not None:
        return tajik
    return next((e for e in entries if e.language != "ru"), None)


def _legacy_primary(word: Word, language: str):
    """Старый выбор перевода: та же логика, что primary_translation, но с явным
    языком вместо контекста запроса (в сравнении контекст не годится)."""
    match = next((t for t in word.translations if t.language == language), None)
    if match is not None:
        return match
    tajik = next((t for t in word.translations if t.language == "tg"), None)
    return tajik or (word.translations[0] if word.translations else None)


def compare_reads(db: Session) -> list[tuple[str, int, str]]:
    """Сравнить старый и новый путь чтения по всем словам и языкам.

    Возвращает список (проверка, сколько расхождений, пример первого)."""
    counters: dict[str, int] = defaultdict(int)
    examples: dict[str, str] = {}

    def bump(name: str, detail: str) -> None:
        counters[name] += 1
        examples.setdefault(name, detail)

    words = db.query(Word).order_by(Word.id).all()
    dictionary_languages = {d.id: d.language for d in db.query(Dictionary).all()}
    entries_map = entries_by_concept(db, [w.id for w in words])

    for word in words:
        lang = dictionary_languages.get(word.dictionary_id, "ru")
        entries = entries_map.get(word.id, [])
        own = learning_entry(entries, lang)

        if own is None:
            bump("Есть запись изучаемого языка", f"слово {word.id}: записи {lang} нет")
            continue

        if own.text != word.word:
            bump("Написание совпадает", f"слово {word.id}: «{word.word}» ≠ «{own.text}»")
        if (own.transcription or None) != (word.transcription or None):
            bump(
                "Транскрипция совпадает",
                f"слово {word.id}: «{word.transcription}» ≠ «{own.transcription}»",
            )
        if (own.audio_key or None) != (word.word_audio_key or None):
            bump("Аудио слова совпадает", f"слово {word.id}")

        # Формы: у старого слова они все, у новой записи — только её языка.
        legacy_own_forms = {(f.id, f.language, f.text) for f in word.forms if f.language == lang}
        new_own_forms = {(f.id, f.language, f.text) for f in own.forms}
        if legacy_own_forms != new_own_forms:
            bump(
                "Формы изучаемого языка совпадают",
                f"слово {word.id}: старых {len(legacy_own_forms)}, новых {len(new_own_forms)}",
            )

        # Все формы слова должны найтись среди форм всех его записей.
        all_new_forms = {(f.id, f.language, f.text) for e in entries for f in e.forms}
        legacy_forms = {(f.id, f.language, f.text) for f in word.forms}
        if legacy_forms != all_new_forms:
            bump(
                "Все формы слова на месте",
                f"слово {word.id}: старых {len(legacy_forms)}, новых {len(all_new_forms)}",
            )

        # Переводы: набор (язык, текст, аудио) должен совпасть полностью.
        legacy_translations = {(t.language, t.text, t.audio_key or None) for t in word.translations}
        new_translations = {
            (e.language, e.text, e.audio_key or None) for e in entries if e.language != lang
        }
        if legacy_translations != new_translations:
            only_legacy = legacy_translations - new_translations
            only_new = new_translations - legacy_translations
            bump(
                "Переводы совпадают",
                f"слово {word.id}: потеряно {len(only_legacy)}, лишнее {len(only_new)}",
            )

        # Подсказка на каждом языке чтения: старый и новый выбор обязаны совпасть.
        for language in READING_LANGUAGES:
            old = _legacy_primary(word, language)
            new = native_entry(entries, language)
            old_pair = (old.text, old.audio_key or None) if old is not None else None
            new_pair = (new.text, new.audio_key or None) if new is not None else None
            if old_pair != new_pair:
                bump(
                    f"Подсказка на языке «{language}» совпадает",
                    f"слово {word.id}: {old_pair} ≠ {new_pair}",
                )

    return [(name, count, examples.get(name, "")) for name, count in sorted(counters.items())]


def main() -> int:
    db = SessionLocal()
    try:
        # Язык чтения в контексте запроса не участвует: сравнение задаёт его явно,
        # но старый код всё равно должен видеть осмысленное значение.
        set_content_language_for("ru", "tg")
        mismatches = compare_reads(db)
        total_words = db.query(Word).count()
        print(f"Сравнение старого и нового чтения по {total_words} словам, языки {', '.join(READING_LANGUAGES)}:")
        if not mismatches:
            print("  Расхождений нет — новый путь читает ровно то же самое.")
            return 0
        for name, count, example in mismatches:
            print(f"  РАСХОЖДЕНИЕ  {name}: {count}   ({example})")
        return 1
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
