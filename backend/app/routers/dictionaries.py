from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.deps import Principal, get_current_admin, get_current_principal
from app.core.storage import delete_by_key
from app.database import get_db
from app.models.dictionary import Dictionary, resolve_dictionary_language_label
from app.models.word import Word
from app.schemas.dictionary import DictionaryCreate, DictionaryOut, DictionaryUpdate

router = APIRouter(prefix="/dictionaries", tags=["dictionaries"])


def _visible_to(principal: Principal, dictionary: Dictionary) -> bool:
    """Admins manage drafts too; a regular user (the Flutter app) must never
    see a dictionary -- or by extension any Word in it -- until it's
    published."""
    return principal.role == "admin" or dictionary.is_published


@router.get("", response_model=list[DictionaryOut])
def list_dictionaries(db: Session = Depends(get_db), principal: Principal = Depends(get_current_principal)):
    query = db.query(Dictionary, func.count(Word.id)).outerjoin(Word, Word.dictionary_id == Dictionary.id)
    if principal.role != "admin":
        query = query.filter(Dictionary.is_published.is_(True))
    rows = query.group_by(Dictionary.id).order_by(Dictionary.id).all()

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
    dictionary = Dictionary(
        name=resolve_dictionary_language_label(payload.language),
        language=payload.language,
        is_published=False,
        alphabet=payload.alphabet.strip() if payload.alphabet and payload.alphabet.strip() else None,
    )
    db.add(dictionary)
    db.commit()
    db.refresh(dictionary)
    out = DictionaryOut.model_validate(dictionary)
    out.word_count = 0
    return out


@router.get("/{dictionary_id}", response_model=DictionaryOut)
def get_dictionary(
    dictionary_id: int, db: Session = Depends(get_db), principal: Principal = Depends(get_current_principal)
):
    dictionary = db.get(Dictionary, dictionary_id)
    if dictionary is None or not _visible_to(principal, dictionary):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")
    word_count = db.query(func.count(Word.id)).filter(Word.dictionary_id == dictionary_id).scalar()
    out = DictionaryOut.model_validate(dictionary)
    out.word_count = word_count or 0
    return out


@router.patch("/{dictionary_id}", response_model=DictionaryOut)
def update_dictionary(
    dictionary_id: int,
    payload: DictionaryUpdate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Publishes/unpublishes the dictionary block and/or updates its
    alphabet -- whichever field(s) the request actually sends. There is no
    separate per-Word publish state: every Word already in the dictionary,
    and every one added to it afterwards, follows this single flag."""
    dictionary = db.get(Dictionary, dictionary_id)
    if dictionary is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")

    if payload.is_published is not None:
        dictionary.is_published = payload.is_published
    if payload.alphabet is not None:
        dictionary.alphabet = payload.alphabet.strip() or None
    db.commit()
    db.refresh(dictionary)

    word_count = db.query(func.count(Word.id)).filter(Word.dictionary_id == dictionary_id).scalar()
    out = DictionaryOut.model_validate(dictionary)
    out.word_count = word_count or 0
    return out


@router.delete("/{dictionary_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_dictionary(dictionary_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Deletes the dictionary block and every Word in it. The database
    cascade (Word.dictionary_id has ondelete=CASCADE, and the ORM
    relationship is cascade="all, delete-orphan") already removes the Word
    and WordTranslation rows; what it can't do is clean up the audio/image
    files those rows pointed at, so that's done explicitly here first."""
    dictionary = db.get(Dictionary, dictionary_id)
    if dictionary is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")

    for word in dictionary.words:
        delete_by_key(word.word_audio_key)
        delete_by_key(word.image_key)
        for translation in word.translations:
            delete_by_key(translation.audio_key)

    db.delete(dictionary)
    db.commit()
    return None
