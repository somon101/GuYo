"""Admin Web: раздел «Языки».

Язык -- это слой языковых записей поверх общих понятий, поэтому здесь он и
заводится: одна строка вместо правки кода. Слова появляются отдельно -- в
карточке понятия, импортом или ИИ-генератором, -- и раздел показывает, сколько
их уже есть и где чего не хватает (озвучки, транскрипции, форм).
"""

import re

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin
from app.database import get_db
from app.models.concept import PhraseEntry, WordEntry, WordEntryForm
from app.models.language import Language
from app.schemas.language import LanguageDetail, LanguageIn, LanguageOut, LanguagePatch

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
    )
    db.add(language)
    db.commit()
    db.refresh(language)
    return _detail(db, language)


@router.patch("/{code}", response_model=LanguageDetail)
def update_language(
    code: str,
    payload: LanguagePatch,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Название, самоназвание, алфавит, порядок и включён ли язык.

    Выключенный язык остаётся со своими записями, но людям не предлагается."""
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
    if payload.sort_order is not None:
        language.sort_order = payload.sort_order
    db.commit()
    db.refresh(language)
    return _detail(db, language)
