from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin, get_current_principal
from app.database import get_db
from app.models.dictionary import Dictionary
from app.models.word import Word
from app.schemas.dictionary import DictionaryCreate, DictionaryOut

router = APIRouter(prefix="/dictionaries", tags=["dictionaries"])


@router.get("", response_model=list[DictionaryOut])
def list_dictionaries(db: Session = Depends(get_db), _principal=Depends(get_current_principal)):
    rows = (
        db.query(Dictionary, func.count(Word.id))
        .outerjoin(Word, Word.dictionary_id == Dictionary.id)
        .group_by(Dictionary.id)
        .order_by(Dictionary.id)
        .all()
    )
    result = []
    for dictionary, word_count in rows:
        out = DictionaryOut.model_validate(dictionary)
        out.word_count = word_count
        result.append(out)
    return result


@router.post("", response_model=DictionaryOut, status_code=status.HTTP_201_CREATED)
def create_dictionary(
    payload: DictionaryCreate, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    dictionary = Dictionary(name=payload.name, language=payload.language)
    db.add(dictionary)
    db.commit()
    db.refresh(dictionary)
    out = DictionaryOut.model_validate(dictionary)
    out.word_count = 0
    return out


@router.get("/{dictionary_id}", response_model=DictionaryOut)
def get_dictionary(dictionary_id: int, db: Session = Depends(get_db), _principal=Depends(get_current_principal)):
    dictionary = db.get(Dictionary, dictionary_id)
    if dictionary is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")
    word_count = db.query(func.count(Word.id)).filter(Word.dictionary_id == dictionary_id).scalar()
    out = DictionaryOut.model_validate(dictionary)
    out.word_count = word_count or 0
    return out
