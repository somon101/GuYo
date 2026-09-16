from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile, status
from sqlalchemy.orm import Session

from app.core.deps import Principal, get_current_admin, get_current_principal
from app.core.storage import delete_by_key, save_upload, url_for_key
from app.database import get_db
from app.models.dictionary import Dictionary
from app.models.phrase import Phrase, PhraseCategory
from app.schemas.phrase import PhraseOut

router = APIRouter(tags=["phrases"])


def phrase_to_out(phrase: Phrase) -> PhraseOut:
    return PhraseOut(
        id=phrase.id,
        dictionary_id=phrase.dictionary_id,
        category_id=phrase.category_id,
        category_name=phrase.category.name if phrase.category is not None else None,
        original=phrase.original,
        transcription=phrase.transcription,
        translation_tg=phrase.translation_tg,
        original_audio_url=url_for_key(phrase.original_audio_key),
        translation_audio_url=url_for_key(phrase.translation_audio_key),
        created_at=phrase.created_at,
        updated_at=phrase.updated_at,
    )


def _get_dictionary_or_404(
    db: Session, dictionary_id: int, principal: Principal | None = None
) -> Dictionary:
    dictionary = db.get(Dictionary, dictionary_id)
    if dictionary is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")
    if principal is not None and principal.role != "admin" and not dictionary.is_published:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")
    return dictionary


def _get_phrase_or_404(db: Session, phrase_id: int) -> Phrase:
    db_phrase = db.get(Phrase, phrase_id)
    if db_phrase is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Phrase not found")
    return db_phrase


def _resolve_category(db: Session, dictionary_id: int, category_id: int | None) -> PhraseCategory | None:
    """A phrase's category (if any) must belong to the SAME dictionary --
    same rule as Word's categories."""
    if category_id is None:
        return None
    category = db.get(PhraseCategory, category_id)
    if category is None or category.dictionary_id != dictionary_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found in this dictionary")
    return category


@router.get("/dictionaries/{dictionary_id}/phrases", response_model=list[PhraseOut])
def list_phrases(
    dictionary_id: int,
    category_id: int | None = Query(None, description="Filter to a single category; omit for all phrases."),
    db: Session = Depends(get_db),
    principal: Principal = Depends(get_current_principal),
):
    _get_dictionary_or_404(db, dictionary_id, principal)
    query = db.query(Phrase).filter(Phrase.dictionary_id == dictionary_id)
    if category_id is not None:
        query = query.filter(Phrase.category_id == category_id)
    phrases = query.order_by(Phrase.id).all()
    return [phrase_to_out(p) for p in phrases]


@router.post(
    "/dictionaries/{dictionary_id}/phrases",
    response_model=PhraseOut,
    status_code=status.HTTP_201_CREATED,
)
def create_phrase(
    dictionary_id: int,
    original: str = Form(..., min_length=1, max_length=1000),
    translation_tg: str = Form(..., min_length=1, max_length=1000),
    transcription: str | None = Form(None),
    category_id: int | None = Form(None),
    original_audio: UploadFile | None = File(None),
    translation_audio: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Creates a new Phrase, always in the dictionary's own language --
    there is no per-phrase language choice, same rule as Forms: the block
    you're in decides it. The Tajik translation is the other fixed side."""
    _get_dictionary_or_404(db, dictionary_id)
    category = _resolve_category(db, dictionary_id, category_id)

    transcription = transcription.strip() if transcription and transcription.strip() else None

    db_phrase = Phrase(
        dictionary_id=dictionary_id,
        category_id=category.id if category else None,
        original=original.strip(),
        transcription=transcription,
        translation_tg=translation_tg.strip(),
        original_audio_key=save_upload(original_audio, subdir=f"dictionaries/{dictionary_id}/phrase_original_audio"),
        translation_audio_key=save_upload(
            translation_audio, subdir=f"dictionaries/{dictionary_id}/phrase_translation_audio"
        ),
    )
    db.add(db_phrase)
    db.commit()
    db.refresh(db_phrase)
    return phrase_to_out(db_phrase)


@router.get("/phrases/{phrase_id}", response_model=PhraseOut)
def get_phrase(
    phrase_id: int, db: Session = Depends(get_db), principal: Principal = Depends(get_current_principal)
):
    db_phrase = _get_phrase_or_404(db, phrase_id)
    _get_dictionary_or_404(db, db_phrase.dictionary_id, principal)
    return phrase_to_out(db_phrase)


@router.patch("/phrases/{phrase_id}", response_model=PhraseOut)
def update_phrase(
    phrase_id: int,
    original: str | None = Form(None),
    transcription: str | None = Form(None),
    remove_transcription: bool = Form(False),
    translation_tg: str | None = Form(None),
    category_id: int | None = Form(None),
    remove_category: bool = Form(False),
    original_audio: UploadFile | None = File(None),
    remove_original_audio: bool = Form(False),
    translation_audio: UploadFile | None = File(None),
    remove_translation_audio: bool = Form(False),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Updates any subset of a Phrase's independent fields. Each field/file
    is only replaced or removed when explicitly asked for -- exactly the
    same convention as update_word, so touching the translation never
    disturbs the original audio, etc."""
    db_phrase = _get_phrase_or_404(db, phrase_id)

    if original is not None and original.strip():
        db_phrase.original = original.strip()

    if translation_tg is not None and translation_tg.strip():
        db_phrase.translation_tg = translation_tg.strip()

    if remove_transcription:
        db_phrase.transcription = None
    elif transcription is not None and transcription.strip():
        db_phrase.transcription = transcription.strip()

    if remove_category:
        db_phrase.category_id = None
    elif category_id is not None:
        category = _resolve_category(db, db_phrase.dictionary_id, category_id)
        db_phrase.category_id = category.id if category else None

    has_new_original_audio = original_audio is not None and original_audio.filename
    if has_new_original_audio:
        delete_by_key(db_phrase.original_audio_key)
        db_phrase.original_audio_key = save_upload(
            original_audio, subdir=f"dictionaries/{db_phrase.dictionary_id}/phrase_original_audio"
        )
    elif remove_original_audio:
        delete_by_key(db_phrase.original_audio_key)
        db_phrase.original_audio_key = None

    has_new_translation_audio = translation_audio is not None and translation_audio.filename
    if has_new_translation_audio:
        delete_by_key(db_phrase.translation_audio_key)
        db_phrase.translation_audio_key = save_upload(
            translation_audio, subdir=f"dictionaries/{db_phrase.dictionary_id}/phrase_translation_audio"
        )
    elif remove_translation_audio:
        delete_by_key(db_phrase.translation_audio_key)
        db_phrase.translation_audio_key = None

    db.commit()
    db.refresh(db_phrase)
    return phrase_to_out(db_phrase)


@router.delete("/phrases/{phrase_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_phrase(phrase_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    db_phrase = _get_phrase_or_404(db, phrase_id)

    delete_by_key(db_phrase.original_audio_key)
    delete_by_key(db_phrase.translation_audio_key)

    db.delete(db_phrase)
    db.commit()
    return None
