"""Admin Web: mini-phrase templates, mini-phrases with their parts, the part
suggestion helper and the mini-phrase settings."""

import re

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin
from app.database import get_db
from app.mini_phrases import get_mini_phrase_settings, normalize_answer
from app.models.dictionary import Dictionary
from app.models.mini_phrase import (
    TEMPLATE_KINDS,
    WORD_ROLES,
    MiniPhrase,
    MiniPhrasePart,
    MiniPhraseTemplate,
)
from app.models.word import Word, WordForm
from app.schemas.mini_phrase import (
    MiniPhraseAdminOut,
    MiniPhraseIn,
    MiniPhrasePartAdminOut,
    MiniPhraseRoleOut,
    MiniPhraseSettingsIn,
    MiniPhraseSettingsOut,
    MiniPhraseTemplateIn,
    MiniPhraseTemplateOut,
    SuggestedPartOut,
    SuggestPartsIn,
)

router = APIRouter(prefix="/admin", tags=["admin-mini-phrases"])

ROLE_LABELS = {
    "pronoun": "Местоимение (кто)",
    "verb": "Глагол (действие)",
    "noun": "Существительное (что)",
    "adjective": "Прилагательное (какой)",
    "adverb": "Наречие (как)",
    "preposition": "Предлог",
    "number": "Число",
    "other": "Другое",
}


@router.get("/mini-phrases/roles", response_model=list[MiniPhraseRoleOut])
def list_roles(_admin=Depends(get_current_admin)):
    return [MiniPhraseRoleOut(id=r, label=ROLE_LABELS[r]) for r in WORD_ROLES]


# --- Templates ----------------------------------------------------------------


def _template_out(db: Session, t: MiniPhraseTemplate) -> MiniPhraseTemplateOut:
    usage = db.query(func.count(MiniPhrase.id)).filter(MiniPhrase.template_id == t.id).scalar() or 0
    return MiniPhraseTemplateOut(
        id=t.id,
        name=t.name,
        kind=t.kind,
        explanation_ru=t.explanation_ru,
        explanation_tg=t.explanation_tg,
        explanation_uz=t.explanation_uz,
        distractor_count=t.distractor_count,
        enabled=t.enabled,
        usage_count=usage,
    )


def _apply_template(t: MiniPhraseTemplate, payload: MiniPhraseTemplateIn) -> None:
    if payload.kind not in TEMPLATE_KINDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Unknown kind '{payload.kind}'")
    t.name = payload.name.strip()
    t.kind = payload.kind
    t.explanation_ru = (payload.explanation_ru or "").strip() or None
    t.explanation_tg = (payload.explanation_tg or "").strip() or None
    t.explanation_uz = (payload.explanation_uz or "").strip() or None
    t.distractor_count = payload.distractor_count
    t.enabled = payload.enabled


@router.get("/mini-phrase-templates", response_model=list[MiniPhraseTemplateOut])
def list_templates(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    return [_template_out(db, t) for t in db.query(MiniPhraseTemplate).order_by(MiniPhraseTemplate.id).all()]


@router.post("/mini-phrase-templates", response_model=MiniPhraseTemplateOut, status_code=status.HTTP_201_CREATED)
def create_template(payload: MiniPhraseTemplateIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    t = MiniPhraseTemplate()
    _apply_template(t, payload)
    db.add(t)
    db.commit()
    db.refresh(t)
    return _template_out(db, t)


@router.put("/mini-phrase-templates/{template_id}", response_model=MiniPhraseTemplateOut)
def update_template(
    template_id: int, payload: MiniPhraseTemplateIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    t = db.get(MiniPhraseTemplate, template_id)
    if t is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Template not found")
    _apply_template(t, payload)
    db.commit()
    db.refresh(t)
    return _template_out(db, t)


@router.delete("/mini-phrase-templates/{template_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_template(template_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    t = db.get(MiniPhraseTemplate, template_id)
    if t is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Template not found")
    if db.query(MiniPhrase.id).filter(MiniPhrase.template_id == t.id).first() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Шаблон используется мини-фразами — сначала смените им шаблон или отключите его",
        )
    db.delete(t)
    db.commit()


# --- Mini-phrases -------------------------------------------------------------


def _get_dictionary_or_404(db: Session, dictionary_id: int) -> Dictionary:
    d = db.get(Dictionary, dictionary_id)
    if d is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")
    return d


def _mini_phrase_out(mp: MiniPhrase) -> MiniPhraseAdminOut:
    return MiniPhraseAdminOut(
        id=mp.id,
        dictionary_id=mp.dictionary_id,
        template_id=mp.template_id,
        template_name=mp.template.name if mp.template is not None else None,
        text=mp.text,
        translation_tg=mp.translation_tg,
        translation_uz=mp.translation_uz,
        translation_en=mp.translation_en,
        enabled=mp.enabled,
        parts=[
            MiniPhrasePartAdminOut(
                position=p.position,
                text=p.text,
                word_id=p.word_id,
                word=p.word.word if p.word is not None else "",
                word_form_id=p.word_form_id,
                word_form_text=p.word_form.text if p.word_form is not None else None,
                role=p.role,
                word_role=p.word.role if p.word is not None else None,
            )
            for p in mp.parts
        ],
        created_at=mp.created_at,
    )


def _apply_mini_phrase(db: Session, mp: MiniPhrase, dictionary_id: int, payload: MiniPhraseIn) -> None:
    if payload.template_id is not None and db.get(MiniPhraseTemplate, payload.template_id) is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Шаблон не найден")
    text = payload.text.strip()
    if normalize_answer(" ".join(p.text for p in payload.parts)) != normalize_answer(text):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Части вместе должны давать ровно эту фразу (без учёта регистра и знаков препинания)",
        )
    parts = []
    for position, p in enumerate(payload.parts, start=1):
        word = db.get(Word, p.word_id)
        if word is None or word.dictionary_id != dictionary_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Слово для части «{p.text}» не из этого словаря")
        if p.word_form_id is not None:
            form = db.get(WordForm, p.word_form_id)
            if form is None or form.word_id != word.id:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Форма для части «{p.text}» не принадлежит слову")
        if p.role is not None and p.role not in WORD_ROLES:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Неизвестная роль «{p.role}»")
        parts.append(
            MiniPhrasePart(position=position, text=p.text.strip(), word_id=word.id, word_form_id=p.word_form_id, role=p.role)
        )
    mp.template_id = payload.template_id
    mp.text = text
    mp.translation_tg = payload.translation_tg.strip()
    mp.translation_uz = (payload.translation_uz or "").strip() or None
    mp.translation_en = (payload.translation_en or "").strip() or None
    mp.enabled = payload.enabled
    mp.parts.clear()
    db.flush()  # free the (mini_phrase_id, position) slots before re-adding
    mp.parts.extend(parts)


@router.get("/dictionaries/{dictionary_id}/mini-phrases", response_model=list[MiniPhraseAdminOut])
def list_mini_phrases(dictionary_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    _get_dictionary_or_404(db, dictionary_id)
    rows = db.query(MiniPhrase).filter(MiniPhrase.dictionary_id == dictionary_id).order_by(MiniPhrase.id).all()
    return [_mini_phrase_out(mp) for mp in rows]


@router.post(
    "/dictionaries/{dictionary_id}/mini-phrases", response_model=MiniPhraseAdminOut, status_code=status.HTTP_201_CREATED
)
def create_mini_phrase(
    dictionary_id: int, payload: MiniPhraseIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    _get_dictionary_or_404(db, dictionary_id)
    mp = MiniPhrase(dictionary_id=dictionary_id, text="", translation_tg="")
    db.add(mp)
    _apply_mini_phrase(db, mp, dictionary_id, payload)
    db.commit()
    db.refresh(mp)
    return _mini_phrase_out(mp)


@router.get("/mini-phrases/{mini_phrase_id}", response_model=MiniPhraseAdminOut)
def get_mini_phrase(mini_phrase_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    mp = db.get(MiniPhrase, mini_phrase_id)
    if mp is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mini-phrase not found")
    return _mini_phrase_out(mp)


@router.put("/mini-phrases/{mini_phrase_id}", response_model=MiniPhraseAdminOut)
def update_mini_phrase(
    mini_phrase_id: int, payload: MiniPhraseIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    mp = db.get(MiniPhrase, mini_phrase_id)
    if mp is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mini-phrase not found")
    _apply_mini_phrase(db, mp, mp.dictionary_id, payload)
    db.commit()
    db.refresh(mp)
    return _mini_phrase_out(mp)


@router.delete("/mini-phrases/{mini_phrase_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_mini_phrase(mini_phrase_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    mp = db.get(MiniPhrase, mini_phrase_id)
    if mp is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mini-phrase not found")
    db.delete(mp)
    db.commit()


_TOKEN = re.compile(r"[\w'-]+", re.UNICODE)


@router.post("/dictionaries/{dictionary_id}/mini-phrases/suggest-parts", response_model=list[SuggestedPartOut])
def suggest_parts(
    dictionary_id: int, payload: SuggestPartsIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    """Splits the phrase into words and finds each one in the dictionary --
    as a word itself first, else as one of a word's own-language forms.
    Only a suggestion: the admin confirms or fixes every part."""
    dictionary = _get_dictionary_or_404(db, dictionary_id)
    out = []
    for token in _TOKEN.findall(payload.text):
        key = token.lower()
        word = (
            db.query(Word)
            .filter(Word.dictionary_id == dictionary_id, func.lower(func.trim(Word.word)) == key)
            .order_by(Word.id)
            .first()
        )
        form = None
        if word is None:
            form = (
                db.query(WordForm)
                .join(Word, Word.id == WordForm.word_id)
                .filter(
                    Word.dictionary_id == dictionary_id,
                    WordForm.language == dictionary.language,
                    func.lower(func.trim(WordForm.text)) == key,
                )
                .order_by(WordForm.id)
                .first()
            )
            word = form.word if form is not None else None
        out.append(
            SuggestedPartOut(
                text=token,
                word_id=word.id if word else None,
                word=word.word if word else None,
                word_form_id=form.id if form else None,
                word_form_text=form.text if form else None,
                role=word.role if word else None,
            )
        )
    return out


@router.post("/dictionaries/{dictionary_id}/mini-phrases/fill-starter")
def fill_starter_set(dictionary_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Adds the starter mini-phrases whose words exist in this dictionary
    (missing forms are added) and reports what was skipped and why."""
    from app.mini_phrases.starter import fill_starter

    report = fill_starter(db, _get_dictionary_or_404(db, dictionary_id))
    db.commit()
    return report


class GenerateIn(BaseModel):
    count: int = Field(default=20, ge=10, le=50)


class ItemsIn(BaseModel):
    items: list[dict] = Field(max_length=60)


class WordsIn(BaseModel):
    words: list[str] = Field(min_length=1, max_length=30)


@router.get("/dictionaries/{dictionary_id}/mini-phrases/analysis")
def mini_phrase_analysis(dictionary_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Script-only: how many mini-phrases the words allow and which missing
    words would unlock the most. No AI, no tokens."""
    from app.mini_phrases import generate

    return generate.analyze(db, _get_dictionary_or_404(db, dictionary_id))


@router.post("/dictionaries/{dictionary_id}/mini-phrases/generate")
def generate_mini_phrases(
    dictionary_id: int, payload: GenerateIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    """Preview only -- nothing is saved."""
    from app.mini_phrases import generate

    return generate.generate(db, _get_dictionary_or_404(db, dictionary_id), payload.count)


@router.post("/dictionaries/{dictionary_id}/mini-phrases/generate/rephrase")
def rephrase_mini_phrases(
    dictionary_id: int, payload: ItemsIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    from app.mini_phrases import generate

    return generate.rephrase(db, _get_dictionary_or_404(db, dictionary_id), payload.items)


@router.post("/dictionaries/{dictionary_id}/mini-phrases/generate/save")
def save_generated_mini_phrases(
    dictionary_id: int, payload: ItemsIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    from app.mini_phrases import generate

    report = generate.save(db, _get_dictionary_or_404(db, dictionary_id), payload.items)
    db.commit()
    return report


@router.post("/dictionaries/{dictionary_id}/mini-phrases/add-words")
def add_missing_words(
    dictionary_id: int, payload: WordsIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    """Full word cards (translations, role, category, all forms) made by the
    AI for the chosen missing words."""
    from app.mini_phrases import generate

    report = generate.add_words(db, _get_dictionary_or_404(db, dictionary_id), payload.words)
    db.commit()
    return report


# --- Settings -----------------------------------------------------------------


def _settings_out(s) -> MiniPhraseSettingsOut:
    return MiniPhraseSettingsOut(
        points_enabled=s.points_enabled, points_per_correct=s.points_per_correct, max_per_lesson=s.max_per_lesson
    )


@router.get("/mini-phrase-settings", response_model=MiniPhraseSettingsOut)
def get_settings(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    s = get_mini_phrase_settings(db)
    db.commit()
    return _settings_out(s)


@router.patch("/mini-phrase-settings", response_model=MiniPhraseSettingsOut)
def update_settings(payload: MiniPhraseSettingsIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    s = get_mini_phrase_settings(db)
    if payload.points_enabled is not None:
        s.points_enabled = payload.points_enabled
    if payload.points_per_correct is not None:
        s.points_per_correct = payload.points_per_correct
    if payload.max_per_lesson is not None:
        s.max_per_lesson = payload.max_per_lesson
    db.commit()
    return _settings_out(s)
