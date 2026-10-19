"""Готов ли язык к публикации -- и чего ему не хватает.

Язык предлагается людям только на 100%:

* **для изучения** -- у каждого слова и каждой фразы (опубликованных
  словарей) есть запись на этом языке, и у языка есть свои мини-фразы, каждая
  со своим шаблоном этого же языка;
* **как язык перевода** -- на этот язык переведены все слова и фразы, все
  мини-фразы всех изучаемых языков имеют подсказку на нём, все шаблоны
  объяснены на нём, и переведён интерфейс приложения.

Каждая проверка возвращает список недостатков: что именно, сколько, и
несколько примеров -- чтобы в админке было видно, что исправлять.
"""

from datetime import datetime, timezone

from sqlalchemy import and_, exists
from sqlalchemy.orm import Session

from app.models.concept import Concept, PhraseConcept, PhraseEntry, WordEntry
from app.models.dictionary import Dictionary
from app.models.language import Language
from app.models.mini_phrase import MiniPhrase, MiniPhraseTemplate, MiniPhraseTemplateTranslation

EXAMPLES = 20

KIND_LEARN = "learn"
KIND_NATIVE = "native"


def _issue(code: str, text: str, count: int, examples: list[str] | None = None, section: str = "") -> dict:
    return {"code": code, "text": text, "count": count, "examples": (examples or [])[:EXAMPLES], "section": section}


def _published_dictionary_ids(db: Session) -> list[int]:
    return [d for (d,) in db.query(Dictionary.id).filter(Dictionary.is_published.is_(True))]


def _concepts_without_entry(db: Session, language: str, dictionary_ids: list[int]) -> tuple[int, list[str]]:
    has_entry = exists().where(
        and_(WordEntry.concept_id == Concept.id, WordEntry.language == language, WordEntry.enabled.is_(True))
    )
    query = db.query(Concept).filter(Concept.dictionary_id.in_(dictionary_ids), ~has_entry)
    total = query.count()
    examples = []
    for concept in query.order_by(Concept.id).limit(EXAMPLES):
        ref = next((e.text for e in concept.entries if e.language == "ru"), None) or (
            concept.entries[0].text if concept.entries else f"#{concept.id}"
        )
        examples.append(f"{ref} (№{concept.id})")
    return total, examples


def _phrases_without_entry(db: Session, language: str, dictionary_ids: list[int]) -> tuple[int, list[str]]:
    has_entry = exists().where(
        and_(PhraseEntry.phrase_concept_id == PhraseConcept.id, PhraseEntry.language == language)
    )
    query = db.query(PhraseConcept).filter(PhraseConcept.dictionary_id.in_(dictionary_ids), ~has_entry)
    total = query.count()
    examples = []
    for concept in query.order_by(PhraseConcept.id).limit(EXAMPLES):
        ref = next((e.text for e in concept.entries if e.language == "ru"), None) or (
            concept.entries[0].text if concept.entries else f"#{concept.id}"
        )
        examples.append(f"{ref} (№{concept.id})")
    return total, examples


def check_learn(db: Session, language: str) -> list[dict]:
    """Чего не хватает, чтобы язык можно было выбрать для изучения."""
    issues = []
    dictionary_ids = _published_dictionary_ids(db)
    if not dictionary_ids:
        return [_issue("no_dictionary", "Нет ни одного опубликованного словаря", 1, section="base")]

    count, examples = _concepts_without_entry(db, language, dictionary_ids)
    if count:
        issues.append(_issue("words", f"Нет слова на этом языке: {count}", count, examples, "words"))

    count, examples = _phrases_without_entry(db, language, dictionary_ids)
    if count:
        issues.append(_issue("phrases", f"Нет фразы на этом языке: {count}", count, examples, "phrases"))

    minis = (
        db.query(MiniPhrase)
        .filter(MiniPhrase.dictionary_id.in_(dictionary_ids), MiniPhrase.enabled.is_(True), MiniPhrase.language == language)
        .order_by(MiniPhrase.id)
        .all()
    )
    if not minis:
        issues.append(_issue("mini_phrases", "Нет ни одной мини-фразы на этом языке", 1, section="mini_phrases"))
    else:
        bad = [
            mp
            for mp in minis
            if mp.template is None or (mp.template.language or "") != language or not mp.template.enabled
        ]
        if bad:
            issues.append(
                _issue(
                    "mini_phrase_templates",
                    f"Мини-фразы без шаблона этого языка: {len(bad)}",
                    len(bad),
                    [mp.text for mp in bad],
                    "mini_phrases",
                )
            )
    return issues


def _learn_languages(db: Session) -> list[str]:
    return [
        code
        for (code,) in db.query(Language.code).filter(Language.is_enabled.is_(True), Language.learn_published.is_(True))
    ]


def check_native(db: Session, language: str) -> list[dict]:
    """Чего не хватает, чтобы язык можно было выбрать языком перевода."""
    from app.mini_phrases.service import _record_translation

    issues = []
    lang = db.get(Language, language)
    dictionary_ids = _published_dictionary_ids(db)
    if not dictionary_ids:
        return [_issue("no_dictionary", "Нет ни одного опубликованного словаря", 1, section="base")]

    count, examples = _concepts_without_entry(db, language, dictionary_ids)
    if count:
        issues.append(_issue("words", f"Нет перевода слова на этот язык: {count}", count, examples, "words"))

    count, examples = _phrases_without_entry(db, language, dictionary_ids)
    if count:
        issues.append(_issue("phrases", f"Нет перевода фразы на этот язык: {count}", count, examples, "phrases"))

    # Подсказки мини-фраз всех изучаемых языков (кроме самого этого языка).
    others = [code for code in _learn_languages(db) if code != language]
    missing = []
    if others:
        minis = (
            db.query(MiniPhrase)
            .filter(
                MiniPhrase.dictionary_id.in_(dictionary_ids),
                MiniPhrase.enabled.is_(True),
                MiniPhrase.language.in_(others),
            )
            .order_by(MiniPhrase.id)
            .all()
        )
        missing = [mp for mp in minis if not (_record_translation(db, mp, language) or "").strip()]
    if missing:
        issues.append(
            _issue(
                "mini_phrase_translations",
                f"Мини-фразы без подсказки на этом языке: {len(missing)}",
                len(missing),
                [f"{mp.text} ({mp.language})" for mp in missing],
                "mini_phrases",
            )
        )

    # Объяснения всех включённых шаблонов, которыми пользуются мини-фразы.
    used = (
        db.query(MiniPhraseTemplate)
        .filter(
            MiniPhraseTemplate.enabled.is_(True),
            exists().where(and_(MiniPhrase.template_id == MiniPhraseTemplate.id, MiniPhrase.enabled.is_(True))),
        )
        .order_by(MiniPhraseTemplate.id)
        .all()
    )
    explained = {
        t
        for (t,) in db.query(MiniPhraseTemplateTranslation.template_id).filter(
            MiniPhraseTemplateTranslation.language == language, MiniPhraseTemplateTranslation.text != ""
        )
    }
    unexplained = [
        t
        for t in used
        if t.id not in explained and not (getattr(t, f"explanation_{language}", None) or "").strip()
    ]
    if unexplained:
        issues.append(
            _issue(
                "template_explanations",
                f"Шаблоны без объяснения на этом языке: {len(unexplained)}",
                len(unexplained),
                [f"{t.name} ({t.language or '—'})" for t in unexplained],
                "templates",
            )
        )

    if lang is not None and not lang.ui_ready:
        issues.append(_issue("ui", "Интерфейс приложения не переведён на этот язык", 1, section="ui"))
    return issues


def check(db: Session, language: str, kind: str) -> list[dict]:
    return check_learn(db, language) if kind == KIND_LEARN else check_native(db, language)


def store_check(db: Session, language: Language) -> dict:
    """Проверяет язык по обоим видам и запоминает результат. Не коммитит."""
    result = {
        "checked_at": datetime.now(timezone.utc).isoformat(),
        KIND_LEARN: check_learn(db, language.code),
        KIND_NATIVE: check_native(db, language.code),
    }
    language.last_check = result
    return result


def _published_count(db: Session, field: str) -> int:
    return db.query(Language).filter(Language.is_enabled.is_(True), getattr(Language, field).is_(True)).count()


def recheck_published(db: Session) -> list[str]:
    """Перепроверяет опубликованные языки и снимает публикацию у тех, у кого
    появились недостатки (причина остаётся в last_check). Коммитит.
    Возвращает, что было снято, например ["en:learn"]."""
    removed = []
    for language in db.query(Language).filter(
        (Language.learn_published.is_(True)) | (Language.native_published.is_(True))
    ):
        result = store_check(db, language)
        for kind, field in ((KIND_LEARN, "learn_published"), (KIND_NATIVE, "native_published")):
            if getattr(language, field) and result[kind]:
                # Never the last published language of a kind: people would be
                # left with nothing to choose. It stays, and the admin sees why.
                if _published_count(db, field) <= 1:
                    result.setdefault("kept", []).append(kind)
                    continue
                setattr(language, field, False)
                result.setdefault("unpublished", []).append(
                    {"kind": kind, "at": result["checked_at"], "reason": [i["text"] for i in result[kind]]}
                )
                removed.append(f"{language.code}:{kind}")
        language.last_check = dict(result)
    db.commit()
    return removed


def published_codes(db: Session, kind: str) -> set[str]:
    field = Language.learn_published if kind == KIND_LEARN else Language.native_published
    return {code for (code,) in db.query(Language.code).filter(Language.is_enabled.is_(True), field.is_(True))}


def unavailable_for(db: Session, user) -> list[str]:
    """Which of this person's languages are no longer published: "learning"
    and/or "native". The app then asks them to pick another one."""
    out = []
    learning = user.learning_language or "ru"
    if learning not in published_codes(db, KIND_LEARN):
        out.append("learning")
    if user.translation_language not in published_codes(db, KIND_NATIVE):
        out.append("native")
    return out


def require_published(db: Session, code: str | None, kind: str) -> None:
    """422 when a person picks a language that is not published for this use."""
    from fastapi import HTTPException, status

    if code is None:
        return
    if code not in published_codes(db, kind):
        what = "для изучения" if kind == KIND_LEARN else "как язык перевода"
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=f"Этот язык пока недоступен {what}")
