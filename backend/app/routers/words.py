from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin, get_current_principal
from app.core.storage import delete_by_key, save_upload, url_for_key
from app.database import get_db
from app.models.dictionary import Dictionary
from app.models.word import Word
from app.schemas.word import WordOut

router = APIRouter(tags=["words"])


def word_to_out(word: Word) -> WordOut:
    return WordOut(
        id=word.id,
        dictionary_id=word.dictionary_id,
        word=word.word,
        translation=word.translation,
        transcription=word.transcription,
        word_audio_url=url_for_key(word.word_audio_key),
        translation_audio_url=url_for_key(word.translation_audio_key),
        image_url=url_for_key(word.image_key),
        created_at=word.created_at,
        updated_at=word.updated_at,
    )


def _get_dictionary_or_404(db: Session, dictionary_id: int) -> Dictionary:
    dictionary = db.get(Dictionary, dictionary_id)
    if dictionary is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")
    return dictionary


@router.get("/dictionaries/{dictionary_id}/words", response_model=list[WordOut])
def list_words(dictionary_id: int, db: Session = Depends(get_db), _principal=Depends(get_current_principal)):
    _get_dictionary_or_404(db, dictionary_id)
    words = (
        db.query(Word)
        .filter(Word.dictionary_id == dictionary_id)
        .order_by(Word.id)
        .all()
    )
    return [word_to_out(w) for w in words]


@router.post(
    "/dictionaries/{dictionary_id}/words",
    response_model=WordOut,
    status_code=status.HTTP_201_CREATED,
)
def create_word(
    dictionary_id: int,
    word: str = Form(..., min_length=1, max_length=255),
    translation: str = Form(..., min_length=1, max_length=255),
    transcription: str | None = Form(None),
    word_audio: UploadFile | None = File(None),
    translation_audio: UploadFile | None = File(None),
    image: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    _get_dictionary_or_404(db, dictionary_id)

    transcription = transcription.strip() if transcription and transcription.strip() else None

    db_word = Word(
        dictionary_id=dictionary_id,
        word=word.strip(),
        translation=translation.strip(),
        transcription=transcription,
        word_audio_key=save_upload(word_audio, subdir=f"dictionaries/{dictionary_id}/word_audio"),
        translation_audio_key=save_upload(
            translation_audio, subdir=f"dictionaries/{dictionary_id}/translation_audio"
        ),
        image_key=save_upload(image, subdir=f"dictionaries/{dictionary_id}/images"),
    )
    db.add(db_word)
    db.commit()
    db.refresh(db_word)
    return word_to_out(db_word)


@router.get("/words/{word_id}", response_model=WordOut)
def get_word(word_id: int, db: Session = Depends(get_db), _principal=Depends(get_current_principal)):
    db_word = db.get(Word, word_id)
    if db_word is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Word not found")
    return word_to_out(db_word)


@router.patch("/words/{word_id}", response_model=WordOut)
def update_word(
    word_id: int,
    word: str | None = Form(None),
    translation: str | None = Form(None),
    transcription: str | None = Form(None),
    remove_transcription: bool = Form(False),
    word_audio: UploadFile | None = File(None),
    translation_audio: UploadFile | None = File(None),
    image: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    db_word = db.get(Word, word_id)
    if db_word is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Word not found")

    if word is not None and word.strip():
        db_word.word = word.strip()
    if translation is not None and translation.strip():
        db_word.translation = translation.strip()
    if remove_transcription:
        db_word.transcription = None
    elif transcription is not None and transcription.strip():
        db_word.transcription = transcription.strip()

    if word_audio is not None and word_audio.filename:
        delete_by_key(db_word.word_audio_key)
        db_word.word_audio_key = save_upload(
            word_audio, subdir=f"dictionaries/{db_word.dictionary_id}/word_audio"
        )
    if translation_audio is not None and translation_audio.filename:
        delete_by_key(db_word.translation_audio_key)
        db_word.translation_audio_key = save_upload(
            translation_audio, subdir=f"dictionaries/{db_word.dictionary_id}/translation_audio"
        )
    if image is not None and image.filename:
        delete_by_key(db_word.image_key)
        db_word.image_key = save_upload(image, subdir=f"dictionaries/{db_word.dictionary_id}/images")

    db.commit()
    db.refresh(db_word)
    return word_to_out(db_word)


@router.delete("/words/{word_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_word(word_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    db_word = db.get(Word, word_id)
    if db_word is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Word not found")

    delete_by_key(db_word.word_audio_key)
    delete_by_key(db_word.translation_audio_key)
    delete_by_key(db_word.image_key)

    db.delete(db_word)
    db.commit()
    return None
