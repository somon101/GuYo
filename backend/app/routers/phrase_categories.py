from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.deps import Principal, get_current_admin, get_current_principal
from app.database import get_db
from app.models.dictionary import Dictionary
from app.models.phrase import Phrase, PhraseCategory
from app.schemas.phrase import PhraseCategoryCreate, PhraseCategoryOut

router = APIRouter(tags=["phrase-categories"])


def _get_dictionary_or_404(db: Session, dictionary_id: int, principal: Principal) -> Dictionary:
    """Same visibility rule as words.py/categories.py: a draft dictionary
    (and everything filed under it, phrase categories included) stays
    invisible to anyone but an admin."""
    dictionary = db.get(Dictionary, dictionary_id)
    if dictionary is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")
    if principal.role != "admin" and not dictionary.is_published:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")
    return dictionary


@router.get("/dictionaries/{dictionary_id}/phrase-categories", response_model=list[PhraseCategoryOut])
def list_phrase_categories(
    dictionary_id: int, db: Session = Depends(get_db), principal: Principal = Depends(get_current_principal)
):
    _get_dictionary_or_404(db, dictionary_id, principal)
    rows = (
        db.query(PhraseCategory, func.count(Phrase.id))
        .outerjoin(Phrase, Phrase.category_id == PhraseCategory.id)
        .filter(PhraseCategory.dictionary_id == dictionary_id)
        .group_by(PhraseCategory.id)
        .order_by(PhraseCategory.id)
        .all()
    )
    result = []
    for category, phrase_count in rows:
        out = PhraseCategoryOut.model_validate(category)
        out.phrase_count = phrase_count
        result.append(out)
    return result


@router.post(
    "/dictionaries/{dictionary_id}/phrase-categories",
    response_model=PhraseCategoryOut,
    status_code=status.HTTP_201_CREATED,
)
def create_phrase_category(
    dictionary_id: int,
    payload: PhraseCategoryCreate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    dictionary = db.get(Dictionary, dictionary_id)
    if dictionary is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")

    name = payload.name.strip()
    exists = (
        db.query(PhraseCategory)
        .filter(PhraseCategory.dictionary_id == dictionary_id, PhraseCategory.name == name)
        .first()
    )
    if exists is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Category already exists in this dictionary"
        )

    category = PhraseCategory(dictionary_id=dictionary_id, name=name)
    db.add(category)
    db.commit()
    db.refresh(category)
    out = PhraseCategoryOut.model_validate(category)
    out.phrase_count = 0
    return out
