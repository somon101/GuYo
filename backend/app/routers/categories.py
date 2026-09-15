from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.deps import Principal, get_current_admin, get_current_principal
from app.database import get_db
from app.models.category import Category
from app.models.dictionary import Dictionary
from app.models.word import Word
from app.schemas.category import CategoryCreate, CategoryOut

router = APIRouter(tags=["categories"])


def _get_dictionary_or_404(db: Session, dictionary_id: int, principal: Principal) -> Dictionary:
    """Same visibility rule as words.py's helper of the same name: a draft
    dictionary (and everything filed under it, categories included) stays
    invisible to anyone but an admin."""
    dictionary = db.get(Dictionary, dictionary_id)
    if dictionary is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")
    if principal.role != "admin" and not dictionary.is_published:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")
    return dictionary


@router.get("/dictionaries/{dictionary_id}/categories", response_model=list[CategoryOut])
def list_categories(
    dictionary_id: int, db: Session = Depends(get_db), principal: Principal = Depends(get_current_principal)
):
    _get_dictionary_or_404(db, dictionary_id, principal)
    rows = (
        db.query(Category, func.count(Word.id))
        .outerjoin(Word, Word.category_id == Category.id)
        .filter(Category.dictionary_id == dictionary_id)
        .group_by(Category.id)
        .order_by(Category.id)
        .all()
    )
    result = []
    for category, word_count in rows:
        out = CategoryOut.model_validate(category)
        out.word_count = word_count
        result.append(out)
    return result


@router.post(
    "/dictionaries/{dictionary_id}/categories", response_model=CategoryOut, status_code=status.HTTP_201_CREATED
)
def create_category(
    dictionary_id: int,
    payload: CategoryCreate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    dictionary = db.get(Dictionary, dictionary_id)
    if dictionary is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")

    name = payload.name.strip()
    exists = (
        db.query(Category)
        .filter(Category.dictionary_id == dictionary_id, Category.name == name)
        .first()
    )
    if exists is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Category already exists in this dictionary")

    category = Category(dictionary_id=dictionary_id, name=name)
    db.add(category)
    db.commit()
    db.refresh(category)
    out = CategoryOut.model_validate(category)
    out.word_count = 0
    return out
