"""Перенос данных в многоязычную структуру (этап 2 плана).

Раскладывает старую структуру («слово + переводы», «фраза + переводы») на
понятия и языковые записи. Запускается **на копии боевой базы** и только потом,
на этапе 8, на бою: см. docs/multilingual-migration.md.

Главные правила:

1. **Языковая запись языка словаря СОХРАНЯЕТ id слова** (`word_entries.id =
   words.id`), а формы — id форм (`word_entry_forms.id = word_forms.id`). Тогда
   прогресс, память, уровни, история ответов, рейтинг, достижения и части
   мини-фраз (они ссылаются на слово и форму по id) продолжают работать без
   единого изменения.
2. **Понятие получает тот же id**, что слово/фраза. Таблицы разные, конфликта
   нет, зато перенос прозрачен: понятие 705 — это слово 705.
3. **Идемпотентность**: слово уже перенесено, если существует языковая запись с
   его id; фраза — если существует понятие с её id. Повторный запуск ничего не
   дублирует.
4. **Перевода как сущности больше нет**: каждая строка `word_translations`
   становится языковой записью того же понятия, а её `audio_key` — аудио этой
   записи. Формы разъезжаются по записям своего языка.

Запуск: `python -m app.multilingual_backfill`
"""

from __future__ import annotations

import sys

from sqlalchemy import func, text
from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.models.concept import Concept, ConceptTopic, PhraseConcept, PhraseEntry, WordEntry, WordEntryForm
from app.models.dictionary import Dictionary
from app.models.mini_phrase import MiniPhrase
from app.models.phrase import Phrase
from app.models.word import Word


def _language_of(db: Session, dictionary_id: int) -> str:
    dictionary = db.get(Dictionary, dictionary_id)
    return dictionary.language if dictionary is not None else "ru"


def backfill_words(db: Session) -> dict:
    """Слова → понятия + языковые записи (язык словаря сохраняет id слова)."""
    created_concepts = created_entries = created_forms = created_topics = 0
    skipped = 0

    dictionary_languages: dict[int, str] = {}
    words = db.query(Word).order_by(Word.id).all()
    for word in words:
        # Идемпотентность: языковая запись с id слова уже есть -- слово перенесено.
        if db.get(WordEntry, word.id) is not None:
            skipped += 1
            continue

        lang = dictionary_languages.get(word.dictionary_id)
        if lang is None:
            lang = _language_of(db, word.dictionary_id)
            dictionary_languages[word.dictionary_id] = lang

        concept = Concept(
            id=word.id,
            dictionary_id=word.dictionary_id,
            category_id=word.category_id,
            importance=word.importance,
            role=word.role,
            image_key=word.image_key,
        )
        db.add(concept)
        created_concepts += 1

        own = WordEntry(
            id=word.id,
            concept_id=concept.id,
            language=lang,
            text=word.word,
            transcription=word.transcription,
            audio_key=word.word_audio_key,
        )
        db.add(own)
        created_entries += 1

        for link in word.topic_links:
            db.add(ConceptTopic(concept_id=concept.id, topic=link.topic))
            created_topics += 1

        # Формы: своему языку -- своя запись (id формы сохраняем).
        entries_by_language: dict[str, WordEntry] = {lang: own}
        for form in word.forms:
            entry = entries_by_language.get(form.language)
            if entry is None:
                # Язык, у которого есть формы, но нет перевода: создаём запись
                # без текста перевода -- иначе формы потерялись бы.
                entry = WordEntry(concept_id=concept.id, language=form.language, text="")
                db.add(entry)
                db.flush()
                entries_by_language[form.language] = entry
                created_entries += 1
            db.add(
                WordEntryForm(id=form.id, word_entry_id=entry.id, language=form.language, text=form.text)
            )
            created_forms += 1

        # Переводы → языковые записи того же понятия.
        for translation in word.translations:
            if translation.language in entries_by_language:
                entry = entries_by_language[translation.language]
                # Перевод есть -- заполняем текст, если запись создана формой.
                if not entry.text:
                    entry.text = translation.text
                if entry.audio_key is None:
                    entry.audio_key = translation.audio_key
                continue
            entry = WordEntry(
                concept_id=concept.id,
                language=translation.language,
                text=translation.text,
                audio_key=translation.audio_key,
            )
            db.add(entry)
            created_entries += 1
            entries_by_language[translation.language] = entry

        if created_concepts % 500 == 0:
            db.flush()

    return {
        "words": len(words),
        "skipped": skipped,
        "concepts": created_concepts,
        "entries": created_entries,
        "forms": created_forms,
        "topics": created_topics,
    }


def backfill_phrases(db: Session) -> dict:
    """Фразы → понятие + запись на каждый язык (аудио перевода — таджикской)."""
    created_concepts = created_entries = 0
    skipped = 0

    dictionary_languages: dict[int, str] = {}
    phrases = db.query(Phrase).order_by(Phrase.id).all()
    for phrase in phrases:
        # Идемпотентность: понятие с id фразы уже есть -- фраза перенесена.
        if db.get(PhraseConcept, phrase.id) is not None:
            skipped += 1
            continue

        lang = dictionary_languages.get(phrase.dictionary_id)
        if lang is None:
            lang = _language_of(db, phrase.dictionary_id)
            dictionary_languages[phrase.dictionary_id] = lang

        concept = PhraseConcept(
            id=phrase.id, dictionary_id=phrase.dictionary_id, category_id=phrase.category_id
        )
        db.add(concept)
        created_concepts += 1

        db.add(
            PhraseEntry(
                phrase_concept_id=concept.id,
                language=lang,
                text=phrase.original,
                transcription=phrase.transcription,
                audio_key=phrase.original_audio_key,
            )
        )
        created_entries += 1

        # Аудио перевода в старой структуре ОДНО на фразу, а не на язык: отдаём
        # его таджикской записи (таджикский -- язык перевода по умолчанию).
        db.add(
            PhraseEntry(
                phrase_concept_id=concept.id,
                language="tg",
                text=phrase.translation_tg,
                audio_key=phrase.translation_audio_key,
            )
        )
        created_entries += 1
        if phrase.translation_uz:
            db.add(
                PhraseEntry(phrase_concept_id=concept.id, language="uz", text=phrase.translation_uz)
            )
            created_entries += 1
        if phrase.translation_en:
            db.add(
                PhraseEntry(phrase_concept_id=concept.id, language="en", text=phrase.translation_en)
            )
            created_entries += 1

    return {"phrases": len(phrases), "skipped": skipped, "concepts": created_concepts, "entries": created_entries}


def backfill_mini_phrase_languages(db: Session) -> int:
    """Мини-фразам -- язык их словаря (колонка появилась в 2f7a1c4d9e05).

    Только через явное соединение с словарём: вариант через
    `.update({MiniPhrase.language: Dictionary.language})` порождает UPDATE с
    декартовым произведением (SQLAlchemy сама об этом предупреждает), и язык
    может приехать от ЧУЖОГО словаря."""
    result = db.execute(
        text(
            "update mini_phrases m set language = d.language "
            "from dictionaries d "
            "where d.id = m.dictionary_id and (m.language is distinct from d.language)"
        )
    )
    return int(result.rowcount or 0)


def backfill_mini_phrase_concepts(db: Session) -> int:
    """Фразам без понятия -- своё понятие.

    Понятие мини-фразы -- это смысл, общий для языков; языковые записи
    ссылаются на него. Миграция a3d7f0c62e19 проставила понятия уже
    существующим фразам, а эта функция доделывает те, что появились другим
    путём (импорт, старый код), чтобы связь никогда не оставалась пустой."""
    rows = db.execute(
        text("select id, dictionary_id from mini_phrases where concept_id is null order by id")
    ).fetchall()
    for mp_id, dictionary_id in rows:
        concept_id = db.execute(
            text("insert into mini_phrase_concepts (dictionary_id) values (:d) returning id"),
            {"d": dictionary_id},
        ).scalar()
        db.execute(
            text("update mini_phrases set concept_id = :c where id = :m"),
            {"c": concept_id, "m": mp_id},
        )
    return len(rows)


def verify(db: Session) -> list[tuple[str, bool, str]]:
    """Сверка переноса: каждая цифра старой структуры должна найтись в новой.

    Возвращает список (проверка, прошла ли, подробность) -- этот же список
    используется на бою на этапе 8, поэтому проверки не зависят от словаря."""
    checks: list[tuple[str, bool, str]] = []

    def scalar(sql: str) -> int:
        return int(db.execute(text(sql)).scalar() or 0)

    def check(name: str, ok: bool, detail: str = "") -> None:
        checks.append((name, bool(ok), detail))

    words = scalar("select count(*) from words")
    phrases = scalar("select count(*) from phrases")
    forms = scalar("select count(*) from word_forms")
    topics = scalar("select count(*) from word_topics")
    translations = scalar("select count(*) from word_translations")

    concepts = scalar("select count(*) from concepts")
    check("Понятия = слова", concepts == words, f"{concepts} / {words}")
    phrase_concepts = scalar("select count(*) from phrase_concepts")
    check("Понятия фраз = фразы", phrase_concepts == phrases, f"{phrase_concepts} / {phrases}")
    entry_forms = scalar("select count(*) from word_entry_forms")
    check("Формы = старые формы", entry_forms == forms, f"{entry_forms} / {forms}")
    concept_topics = scalar("select count(*) from concept_topics")
    check("Темы = старые темы", concept_topics == topics, f"{concept_topics} / {topics}")

    kept_ids = scalar(
        "select count(*) from word_entries e "
        "join words w on w.id = e.id "
        "join dictionaries d on d.id = w.dictionary_id "
        "where e.language = d.language"
    )
    check("Записи языка словаря сохранили id слов", kept_ids == words, f"{kept_ids} / {words}")

    foreign_forms = scalar(
        "select count(*) from word_entry_forms f "
        "join word_entries e on e.id = f.word_entry_id "
        "where e.language <> f.language"
    )
    check("Формы лежат в записи СВОЕГО языка", foreign_forms == 0, f"чужих: {foreign_forms}")

    kept_forms = scalar("select count(*) from word_entry_forms f join word_forms w on w.id = f.id")
    check("Формы сохранили id", kept_forms == forms, f"{kept_forms} / {forms}")

    # Прогресс, память, история, рейтинг и части мини-фраз ссылаются на слово по
    # id -- после переноса это те же id, поэтому все связи обязаны быть живыми.
    progress = scalar("select count(*) from word_progress")
    alive_progress = scalar("select count(*) from word_progress p join word_entries e on e.id = p.word_id")
    check("Прогресс ссылается на живые записи", alive_progress == progress, f"{alive_progress} / {progress}")

    attempts = scalar("select count(*) from word_attempts")
    alive_attempts = scalar("select count(*) from word_attempts a join word_entries e on e.id = a.word_id")
    check("История ответов ссылается на живые записи", alive_attempts == attempts, f"{alive_attempts} / {attempts}")

    parts = scalar("select count(*) from mini_phrase_parts")
    alive_parts = scalar("select count(*) from mini_phrase_parts p join word_entries e on e.id = p.word_id")
    check("Части мини-фраз ссылаются на живые записи", alive_parts == parts, f"{alive_parts} / {parts}")

    dead_forms = scalar(
        "select count(*) from mini_phrase_parts p "
        "where p.word_form_id is not null "
        "and not exists (select 1 from word_entry_forms f where f.id = p.word_form_id)"
    )
    check("Части мини-фраз ссылаются на живые формы", dead_forms == 0, f"битых: {dead_forms}")

    translated = scalar("select count(*) from word_entries e where e.language <> 'ru'")
    check("Записей других языков = переводов", translated == translations, f"{translated} / {translations}")

    # Запись без текста допустима только тогда, когда у неё уже есть формы:
    # форма может прийти раньше перевода (её заводят в карточке языка).
    empty_texts = scalar(
        "select count(*) from word_entries e "
        "where coalesce(e.text, '') = '' "
        "and not exists (select 1 from word_entry_forms f where f.word_entry_id = e.id)"
    )
    check("Нет пустых записей без форм", empty_texts == 0, f"пустых: {empty_texts}")

    mini = scalar("select count(*) from mini_phrases")
    mini_lang = scalar("select count(*) from mini_phrases where language is not null")
    check("У всех мини-фраз проставлен язык", mini_lang == mini, f"{mini_lang} / {mini}")

    phrase_ru = scalar("select count(*) from phrase_entries group by language order by count(*) desc limit 1")
    check("У каждой фразы есть запись основного языка", phrase_ru == phrases, f"{phrase_ru} / {phrases}")

    # Понятие мини-фразы -- смысл, общий для языков; без него языковые записи
    # нельзя связать между собой.
    mini_concepts = scalar("select count(*) from mini_phrases where concept_id is not null")
    check("У каждой мини-фразы есть понятие", mini_concepts == mini, f"{mini_concepts} / {mini}")
    orphan_concepts = scalar(
        "select count(*) from mini_phrase_concepts c "
        "where not exists (select 1 from mini_phrases m where m.concept_id = c.id)"
    )
    check("Нет понятий без фраз", orphan_concepts == 0, f"лишних: {orphan_concepts}")

    # Шаблон описывает порядок частей, а порядок -- свойство языка: у шаблона
    # должен быть проставлен язык.
    templates = scalar("select count(*) from mini_phrase_templates")
    templates_lang = scalar("select count(*) from mini_phrase_templates where language is not null")
    check("У всех шаблонов проставлен язык", templates_lang == templates, f"{templates_lang} / {templates}")

    return checks


def _advance_sequences(db: Session) -> None:
    """После вставки с явными id счётчики надо подвинуть, иначе новые вставки
    упрутся в занятые id."""
    for table in ("concepts", "word_entries", "word_entry_forms", "phrase_concepts"):
        db.execute(
            text(
                "select setval(pg_get_serial_sequence(:t, 'id'), "
                "coalesce((select max(id) from " + table + "), 1))"
            ),
            {"t": table},
        )


def _prime_sequences(db: Session) -> None:
    """Поднять счётчики ДО переноса — не ниже максимумов старых таблиц.

    Языковые записи языка словаря вставляются с явным id (= id слова), а записи
    переводов — обычной вставкой, через счётчик. Если счётчик не поднять заранее,
    он начинает с 1 и выдаёт перевод первый же занятый id: первая версия скрипта
    падала на `word_entries_pkey`, DETAIL «id=705 уже существует»."""
    for table, legacy in (
        ("concepts", ("words", "phrases")),
        ("word_entries", ("words",)),
        ("word_entry_forms", ("word_forms",)),
        ("phrase_concepts", ("phrases",)),
    ):
        source = ", ".join(f"(select max(id) from {t})" for t in legacy)
        db.execute(
            text(
                f"select setval(pg_get_serial_sequence('{table}', 'id'), "
                f"coalesce(greatest({source}, 1), 1))"
            )
        )


def backfill(db: Session) -> dict:
    # Счётчики поднимаем ДО вставок: записи переводов идут через них (см.
    # _prime_sequences).
    _prime_sequences(db)
    words = backfill_words(db)
    db.flush()
    phrases = backfill_phrases(db)
    db.flush()
    mini = backfill_mini_phrase_languages(db)
    db.flush()
    mini_concepts = backfill_mini_phrase_concepts(db)
    db.flush()
    _advance_sequences(db)
    db.commit()
    return {
        "words": words,
        "phrases": phrases,
        "mini_phrases_language_set": mini,
        "mini_phrase_concepts_created": mini_concepts,
    }


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "backfill"
    db = SessionLocal()
    try:
        if mode == "verify":
            checks = verify(db)
            failed = 0
            for name, ok, detail in checks:
                if not ok:
                    failed += 1
                print(("  OK   " if ok else "  БЕДА ") + name + (f"  ({detail})" if detail else ""))
            print(f"Проверок: {len(checks)}, провалено: {failed}")
            return 1 if failed else 0

        print("До переноса:")
        for label, sql in (
            ("слова", "select count(*) from words"),
            ("понятия", "select count(*) from concepts"),
            ("языковые записи", "select count(*) from word_entries"),
            ("фразы", "select count(*) from phrases"),
            ("записи фраз", "select count(*) from phrase_entries"),
            ("мини-фразы без языка", "select count(*) from mini_phrases where language is null"),
        ):
            print(f"  {label}: {int(db.execute(text(sql)).scalar() or 0)}")

        report = backfill(db)

        print("Перенос:")
        print(f"  слова:      {report['words']}")
        print(f"  фразы:      {report['phrases']}")
        print(f"  мини-фразы: язык проставлен у {report['mini_phrases_language_set']}")
        print("После переноса:")
        for label, sql in (
            ("понятия", "select count(*) from concepts"),
            ("языковые записи", "select count(*) from word_entries"),
            ("формы записей", "select count(*) from word_entry_forms"),
            ("темы понятий", "select count(*) from concept_topics"),
            ("понятия фраз", "select count(*) from phrase_concepts"),
            ("записи фраз", "select count(*) from phrase_entries"),
        ):
            print(f"  {label}: {int(db.execute(text(sql)).scalar() or 0)}")

        print("Сверка:")
        failed = 0
        for name, ok, detail in verify(db):
            if not ok:
                failed += 1
            print(("  OK   " if ok else "  БЕДА ") + name + (f"  ({detail})" if detail else ""))
        return 1 if failed else 0
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
