"""Переводы мини-фраз и объяснения шаблонов -- на любые языки из базы.

Источник правды -- таблицы «по строке на язык» (mini_phrase_translations,
mini_phrase_template_translations): добавили язык в админке, и у него сразу
есть место для текста, без миграции и правки кода. Старые колонки
(translation_tg/uz/en, explanation_ru/tg/uz) по-прежнему заполняются зеркалом:
их ещё читают старые места и старые сборки приложения.
"""

from sqlalchemy.orm import Session

from app.models.mini_phrase import (
    MiniPhrase,
    MiniPhraseTemplate,
    MiniPhraseTemplateTranslation,
    MiniPhraseTranslation,
)

LEGACY_TRANSLATIONS = ("tg", "uz", "en")
LEGACY_EXPLANATIONS = ("ru", "tg", "uz")


def translations_of(mp: MiniPhrase) -> dict[str, str]:
    out = {}
    for code in LEGACY_TRANSLATIONS:
        text = (getattr(mp, f"translation_{code}", None) or "").strip()
        if text:
            out[code] = text
    for row in mp.translations or []:
        if (row.text or "").strip():
            out[row.language] = row.text
    return out


def explanations_of(t: MiniPhraseTemplate) -> dict[str, str]:
    out = {}
    for code in LEGACY_EXPLANATIONS:
        text = (getattr(t, f"explanation_{code}", None) or "").strip()
        if text:
            out[code] = text
    for row in t.translations or []:
        if (row.text or "").strip():
            out[row.language] = row.text
    return out


def set_translations(db: Session, mp: MiniPhrase, values: dict[str, str | None]) -> None:
    """Сохраняет переданные языки (пустая строка -- удалить перевод).
    Языки, которых нет в `values`, не трогаются. Не коммитит."""
    rows = {row.language: row for row in (mp.translations or [])}
    for code, raw in values.items():
        text = (raw or "").strip()
        row = rows.get(code)
        if text:
            if row is None:
                row = MiniPhraseTranslation(language=code, text=text[:1000])
                mp.translations.append(row)
            else:
                row.text = text[:1000]
        elif row is not None:
            mp.translations.remove(row)  # delete-orphan removes the row
        if code in LEGACY_TRANSLATIONS:
            if code == "tg":
                mp.translation_tg = text[:500]  # NOT NULL column
            else:
                setattr(mp, f"translation_{code}", text[:500] or None)


def set_explanations(db: Session, t: MiniPhraseTemplate, values: dict[str, str | None]) -> None:
    """То же для объяснений шаблона. Не коммитит."""
    rows = {row.language: row for row in (t.translations or [])}
    for code, raw in values.items():
        text = (raw or "").strip()
        row = rows.get(code)
        if text:
            if row is None:
                row = MiniPhraseTemplateTranslation(language=code, text=text)
                t.translations.append(row)
            else:
                row.text = text
        elif row is not None:
            t.translations.remove(row)  # delete-orphan removes the row
        if code in LEGACY_EXPLANATIONS:
            setattr(t, f"explanation_{code}", text or None)
