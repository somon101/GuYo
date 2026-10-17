"""Admin Web: раздел «Языки».

Язык -- это слой языковых записей поверх общих понятий, поэтому здесь он и
заводится: одна строка вместо правки кода. Слова появляются отдельно -- в
карточке понятия, импортом или ИИ-генератором, -- и раздел показывает, сколько
их уже есть и где чего не хватает (озвучки, транскрипции, форм).
"""

import re

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin
from app.core.storage import delete_by_key, save_upload, url_for_key
from app.database import get_db
from app.models.concept import Concept, PhraseEntry, WordEntry, WordEntryForm
from app.models.language import Language
from app.models.mini_phrase import WORD_ROLES
from app.models.word import Word, WordForm, WordTranslation
from app.schemas.language import (
    LanguageDetail,
    LanguageFormIn,
    LanguageFormOut,
    LanguageIn,
    LanguageOut,
    LanguagePatch,
    LanguageWordDetail,
    LanguageWordPatch,
)

router = APIRouter(prefix="/admin/languages", tags=["admin-languages"])

# Код языка лежит в языковых записях рядом с текстом, поэтому — короткий и
# латинский: de, ar, fa. Русский и таджикский уже ru и tg.
CODE_RE = re.compile(r"^[a-z]{2,3}$")


class LanguagesOut(BaseModel):
    languages: list[LanguageDetail]


def _detail(db: Session, language: Language) -> LanguageDetail:
    entries = db.query(WordEntry).filter(WordEntry.language == language.code)
    forms = (
        db.query(func.count(WordEntryForm.id))
        .join(WordEntry, WordEntry.id == WordEntryForm.word_entry_id)
        .filter(WordEntry.language == language.code)
        .scalar()
        or 0
    )
    return LanguageDetail(
        code=language.code,
        name=language.name,
        native_name=language.native_name,
        alphabet=language.alphabet,
        is_enabled=language.is_enabled,
        sort_order=language.sort_order,
        entries=entries.count(),
        with_audio=entries.filter(WordEntry.audio_key.isnot(None)).count(),
        with_transcription=entries.filter(WordEntry.transcription.isnot(None)).count(),
        forms=int(forms),
        phrase_entries=int(
            db.query(func.count(PhraseEntry.id)).filter(PhraseEntry.language == language.code).scalar() or 0
        ),
        created_at=language.created_at,
    )


@router.get("", response_model=LanguagesOut)
def list_languages(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Языки по порядку, вместе с наполнением каждого."""
    rows = db.query(Language).order_by(Language.sort_order, Language.code).all()
    return LanguagesOut(languages=[_detail(db, row) for row in rows])


@router.post("", response_model=LanguageDetail, status_code=status.HTTP_201_CREATED)
def create_language(
    payload: LanguageIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    """Заводит язык. Слов у него пока нет — это отдельная работа."""
    code = payload.code.strip().lower()
    if not CODE_RE.match(code):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Код языка — две-три латинские буквы, например de или ar",
        )
    if db.get(Language, code) is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Такой язык уже есть")

    last = db.query(func.max(Language.sort_order)).scalar() or 0
    language = Language(
        code=code,
        name=payload.name.strip(),
        native_name=(payload.native_name or "").strip() or None,
        alphabet=(payload.alphabet or "").strip() or None,
        sort_order=int(last) + 1,
        # Строк интерфейса на новом языке в приложении ещё нет: в переключателе
        # интерфейса он появится, когда перевод будет готов (галочка в админке).
        ui_ready=False,
    )
    db.add(language)
    db.commit()
    db.refresh(language)
    from app.core.languages_in_db import forget

    forget()
    return _detail(db, language)


@router.patch("/{code}", response_model=LanguageDetail)
def update_language(
    code: str,
    payload: LanguagePatch,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Название, самоназвание, алфавит, порядок, включён ли язык и переведён
    ли его интерфейс.

    Выключенный язык остаётся со своими записями, но людям не предлагается.
    `ui_ready` управляет только переключателем интерфейса: язык без перевода
    строк всё равно можно учить и читать на нём подсказки."""
    language = db.get(Language, code)
    if language is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Язык не найден")

    if payload.name is not None:
        language.name = payload.name.strip()
    if payload.native_name is not None:
        language.native_name = payload.native_name.strip() or None
    if payload.alphabet is not None:
        language.alphabet = payload.alphabet.strip() or None
    if payload.is_enabled is not None:
        language.is_enabled = payload.is_enabled
    if payload.ui_ready is not None:
        language.ui_ready = payload.ui_ready
    if payload.sort_order is not None:
        language.sort_order = payload.sort_order
    db.commit()
    db.refresh(language)
    # Список языков кэшируется на полминуты; правка должна применяться сразу.
    from app.core.languages_in_db import forget

    forget()
    return _detail(db, language)


# --- Карточка слова в языке ---------------------------------------------------
#
# Здесь правятся только ЯЗЫКОВЫЕ поля: написание, транскрипция, аудио, формы.
# Классификация (роль, важность, категория, темы, картинка) принадлежит понятию
# и правится в разделе «База» -- она одна на все языки.
#
# Каждая запись зеркалится и в старые таблицы: пока приложение читает из них
# частично (текст слова для упражнений), иначе правка была бы видна только новой
# структуре.


def _entry_or_404(db: Session, language: str, entry_id: int) -> WordEntry:
    entry = db.get(WordEntry, entry_id)
    if entry is None or entry.language != language:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Слово не найдено")
    return entry


def _word_detail(db: Session, entry: WordEntry) -> LanguageWordDetail:
    concept = db.get(Concept, entry.concept_id)
    siblings = (
        db.query(WordEntry)
        .filter(WordEntry.concept_id == entry.concept_id, WordEntry.id != entry.id)
        .order_by(WordEntry.id)
        .all()
    )
    return LanguageWordDetail(
        id=entry.id,
        concept_id=entry.concept_id,
        language=entry.language,
        text=entry.text,
        transcription=entry.transcription,
        audio_url=url_for_key(entry.audio_key),
        forms=[LanguageFormOut(id=f.id, text=f.text) for f in entry.forms],
        dictionary_id=concept.dictionary_id if concept is not None else 0,
        # Роль этого языка; значение с понятия -- запасное (см. word_entries.role_for).
        role=entry.role or (concept.role if concept is not None else None),
        importance=concept.importance if concept is not None else 3,
        category_id=concept.category_id if concept is not None else None,
        siblings=[{"language": s.language, "text": s.text} for s in siblings],
    )


def _mirror_text(db: Session, entry: WordEntry, concept: Concept | None) -> None:
    """Переносит написание в старые таблицы, если эта запись -- язык слова."""
    if concept is None:
        return
    word = db.get(Word, concept.id)
    if word is None:
        return
    dictionary = db.get(Language, entry.language)
    del dictionary  # язык словаря здесь не нужен: смотрим по самому слову
    if entry.id == word.id:
        word.word = entry.text
        word.transcription = entry.transcription
    else:
        translation = (
            db.query(WordTranslation)
            .filter(WordTranslation.word_id == word.id, WordTranslation.language == entry.language)
            .first()
        )
        if translation is not None:
            translation.text = entry.text


@router.get("/{language}/words/{entry_id}", response_model=LanguageWordDetail)
def get_language_word(
    language: str, entry_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    """Слово на этом языке: написание, транскрипция, аудио и формы именно языка."""
    return _word_detail(db, _entry_or_404(db, language, entry_id))


@router.patch("/{language}/words/{entry_id}", response_model=LanguageWordDetail)
def update_language_word(
    language: str,
    entry_id: int,
    payload: LanguageWordPatch,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Правит поля этого языка: написание, транскрипцию и роль (часть речи).

    Роль принадлежит языку: одно и то же понятие бывает глаголом в одном языке и
    существительным в другом. Общая классификация (категория, темы, важность,
    картинка) правится в «Базе»."""
    entry = _entry_or_404(db, language, entry_id)
    if payload.text is not None:
        entry.text = payload.text.strip()
    if payload.remove_transcription:
        entry.transcription = None
    elif payload.transcription is not None:
        entry.transcription = payload.transcription.strip() or None
    if payload.remove_role:
        entry.role = None
    elif payload.role is not None:
        value = payload.role.strip() or None
        if value is not None and value not in WORD_ROLES:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Неизвестная роль «{value}»")
        entry.role = value
    db.flush()
    _mirror_text(db, entry, db.get(Concept, entry.concept_id))
    db.commit()
    db.refresh(entry)
    return _word_detail(db, entry)


class GapsIn(BaseModel):
    limit: int = Field(default=20, ge=1, le=60)


class GapsSaveIn(BaseModel):
    items: list[dict] = Field(max_length=60)


@router.get("/{language}/gaps")
def language_gaps(language: str, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Чего не хватает языку: сколько слов без форм и без транскрипции."""
    from app import word_gaps

    return word_gaps.plan(db, language)


@router.post("/{language}/gaps/fill")
def fill_language_gaps(
    language: str,
    payload: GapsIn,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Показ: какие формы и транскрипции предложит модель. Ничего не сохраняет."""
    from app import word_gaps

    return word_gaps.preview(db, language, payload.limit)


@router.post("/{language}/gaps/fill/save")
def save_language_gaps(
    language: str,
    payload: GapsSaveIn,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Сохраняет формы и транскрипции в языковые записи выбранного языка."""
    from app import word_gaps

    return word_gaps.save(db, language, payload.items)


@router.post(
    "/{language}/words/{entry_id}/audio",
    response_model=LanguageWordDetail,
    status_code=status.HTTP_201_CREATED,
)
def upload_language_word_audio(
    language: str,
    entry_id: int,
    audio: UploadFile = File(...),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Озвучка слова на этом языке."""
    entry = _entry_or_404(db, language, entry_id)
    if entry.audio_key:
        delete_by_key(entry.audio_key)
    entry.audio_key = save_upload(audio, subdir=f"languages/{language}/word_audio")
    concept = db.get(Concept, entry.concept_id)
    word = db.get(Word, concept.id) if concept is not None else None
    if word is not None and entry.id == word.id:
        word.word_audio_key = entry.audio_key
    elif word is not None:
        translation = (
            db.query(WordTranslation)
            .filter(WordTranslation.word_id == word.id, WordTranslation.language == language)
            .first()
        )
        if translation is not None:
            translation.audio_key = entry.audio_key
    db.commit()
    db.refresh(entry)
    return _word_detail(db, entry)


@router.delete("/{language}/words/{entry_id}/audio", response_model=LanguageWordDetail)
def delete_language_word_audio(
    language: str, entry_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    entry = _entry_or_404(db, language, entry_id)
    delete_by_key(entry.audio_key)
    entry.audio_key = None
    concept = db.get(Concept, entry.concept_id)
    word = db.get(Word, concept.id) if concept is not None else None
    if word is not None and entry.id == word.id:
        word.word_audio_key = None
    db.commit()
    db.refresh(entry)
    return _word_detail(db, entry)


@router.post(
    "/{language}/words/{entry_id}/forms",
    response_model=LanguageWordDetail,
    status_code=status.HTTP_201_CREATED,
)
def add_language_word_form(
    language: str,
    entry_id: int,
    payload: LanguageFormIn,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Добавляет форму слова на этом языке (падеж, число, склонение)."""
    entry = _entry_or_404(db, language, entry_id)
    text = payload.text.strip()
    if text:
        existing = next((f for f in entry.forms if f.text.strip().lower() == text.lower()), None)
        if existing is None:
            form = WordEntryForm(word_entry_id=entry.id, language=language, text=text)
            db.add(form)
            db.flush()
            concept = db.get(Concept, entry.concept_id)
            word = db.get(Word, concept.id) if concept is not None else None
            if word is not None:
                # Зеркало в старую таблицу форм: её id совпадает с id новой формы,
                # и на неё ссылаются части мини-фраз.
                legacy = db.get(WordForm, form.id)
                if legacy is None:
                    db.add(WordForm(id=form.id, word_id=word.id, language=language, text=text))
    db.commit()
    db.refresh(entry)
    return _word_detail(db, entry)


@router.delete("/{language}/words/{entry_id}/forms/{form_id}", response_model=LanguageWordDetail)
def delete_language_word_form(
    language: str,
    entry_id: int,
    form_id: int,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    entry = _entry_or_404(db, language, entry_id)
    form = db.get(WordEntryForm, form_id)
    if form is None or form.word_entry_id != entry.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Форма не найдена")
    legacy = db.get(WordForm, form_id)
    if legacy is not None:
        db.delete(legacy)
    db.delete(form)
    db.commit()
    db.refresh(entry)
    return _word_detail(db, entry)
