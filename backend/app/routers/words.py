from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin, get_current_principal
from app.core.languages import is_valid_translation_language
from app.core.storage import delete_by_key, save_upload, url_for_key
from app.database import get_db
from app.models.dictionary import Dictionary, DictionaryLanguage
from app.models.word import Word, WordTranslation
from app.schemas.word import WordOut, WordTranslationOut

router = APIRouter(tags=["words"])


def _default_translation_language(dictionary_language: DictionaryLanguage) -> str:
    """A word's translation language was never asked for explicitly before
    this stage. Default it the same way the data migration inferred it for
    existing rows: Russian, unless the dictionary itself is Russian, in
    which case English."""
    return "en" if dictionary_language == DictionaryLanguage.RUSSIAN else "ru"


def translation_to_out(t: WordTranslation) -> WordTranslationOut:
    return WordTranslationOut(id=t.id, language=t.language, text=t.text, audio_url=url_for_key(t.audio_key))


def word_to_out(word: Word) -> WordOut:
    translations = [translation_to_out(t) for t in word.translations]
    primary = translations[0] if translations else None
    return WordOut(
        id=word.id,
        dictionary_id=word.dictionary_id,
        word=word.word,
        transcription=word.transcription,
        word_audio_url=url_for_key(word.word_audio_key),
        image_url=url_for_key(word.image_key),
        quizlet=word.quizlet,
        created_at=word.created_at,
        updated_at=word.updated_at,
        translation=primary.text if primary else None,
        translation_audio_url=primary.audio_url if primary else None,
        translations=translations,
    )


def _get_dictionary_or_404(db: Session, dictionary_id: int) -> Dictionary:
    dictionary = db.get(Dictionary, dictionary_id)
    if dictionary is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")
    return dictionary


def _get_word_or_404(db: Session, word_id: int) -> Word:
    db_word = db.get(Word, word_id)
    if db_word is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Word not found")
    return db_word


def _require_valid_language(language: str) -> None:
    if not is_valid_translation_language(language):
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Unsupported language code")


@router.get("/dictionaries/{dictionary_id}/words", response_model=list[WordOut])
def list_words(dictionary_id: int, db: Session = Depends(get_db), _principal=Depends(get_current_principal)):
    _get_dictionary_or_404(db, dictionary_id)
    words = db.query(Word).filter(Word.dictionary_id == dictionary_id).order_by(Word.id).all()
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
    translation_language: str | None = Form(None),
    transcription: str | None = Form(None),
    word_audio: UploadFile | None = File(None),
    translation_audio: UploadFile | None = File(None),
    image: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    dictionary = _get_dictionary_or_404(db, dictionary_id)

    lang = (translation_language or _default_translation_language(dictionary.language)).strip().lower()
    _require_valid_language(lang)

    transcription = transcription.strip() if transcription and transcription.strip() else None

    db_word = Word(
        dictionary_id=dictionary_id,
        word=word.strip(),
        transcription=transcription,
        word_audio_key=save_upload(word_audio, subdir=f"dictionaries/{dictionary_id}/word_audio"),
        image_key=save_upload(image, subdir=f"dictionaries/{dictionary_id}/images"),
    )
    db.add(db_word)
    db.flush()  # assign db_word.id for the translation + storage path below

    db_translation = WordTranslation(
        word_id=db_word.id,
        language=lang,
        text=translation.strip(),
        audio_key=save_upload(translation_audio, subdir=f"dictionaries/{dictionary_id}/translation_audio/{lang}"),
    )
    db.add(db_translation)

    db.commit()
    db.refresh(db_word)
    return word_to_out(db_word)


@router.get("/words/{word_id}", response_model=WordOut)
def get_word(word_id: int, db: Session = Depends(get_db), _principal=Depends(get_current_principal)):
    return word_to_out(_get_word_or_404(db, word_id))


@router.patch("/words/{word_id}", response_model=WordOut)
def update_word(
    word_id: int,
    word: str | None = Form(None),
    transcription: str | None = Form(None),
    remove_transcription: bool = Form(False),
    quizlet: str | None = Form(None),
    remove_quizlet: bool = Form(False),
    word_audio: UploadFile | None = File(None),
    remove_word_audio: bool = Form(False),
    image: UploadFile | None = File(None),
    remove_image: bool = Form(False),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Updates the Word itself: its text, transcription, own pronunciation,
    image and Quizlet link. Never touches other words, and changing one
    field here never clears the others -- each field/file is only replaced
    or removed when explicitly asked for. Translations are managed through
    the dedicated /words/{id}/translations/{language} endpoints below."""
    db_word = _get_word_or_404(db, word_id)

    if word is not None and word.strip():
        db_word.word = word.strip()

    if remove_transcription:
        db_word.transcription = None
    elif transcription is not None and transcription.strip():
        db_word.transcription = transcription.strip()

    if remove_quizlet:
        db_word.quizlet = None
    elif quizlet is not None and quizlet.strip():
        db_word.quizlet = quizlet.strip()

    has_new_word_audio = word_audio is not None and word_audio.filename
    if has_new_word_audio:
        delete_by_key(db_word.word_audio_key)
        db_word.word_audio_key = save_upload(word_audio, subdir=f"dictionaries/{db_word.dictionary_id}/word_audio")
    elif remove_word_audio:
        delete_by_key(db_word.word_audio_key)
        db_word.word_audio_key = None

    has_new_image = image is not None and image.filename
    if has_new_image:
        delete_by_key(db_word.image_key)
        db_word.image_key = save_upload(image, subdir=f"dictionaries/{db_word.dictionary_id}/images")
    elif remove_image:
        delete_by_key(db_word.image_key)
        db_word.image_key = None

    db.commit()
    db.refresh(db_word)
    return word_to_out(db_word)


@router.delete("/words/{word_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_word(word_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    db_word = _get_word_or_404(db, word_id)

    delete_by_key(db_word.word_audio_key)
    delete_by_key(db_word.image_key)
    for t in db_word.translations:
        delete_by_key(t.audio_key)

    db.delete(db_word)
    db.commit()
    return None


@router.put("/words/{word_id}/translations/{language}", response_model=WordTranslationOut)
def upsert_translation(
    word_id: int,
    language: str,
    text: str = Form(..., min_length=1, max_length=255),
    audio: UploadFile | None = File(None),
    remove_audio: bool = Form(False),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Creates or updates the translation of this word into `language`.
    A word may have at most one translation per language (adding another
    call with the same language just updates it in place) -- this is how a
    future Tajik translation gets added alongside the existing Russian one,
    with its own independent pronunciation audio."""
    language = language.strip().lower()
    _require_valid_language(language)
    db_word = _get_word_or_404(db, word_id)

    existing = next((t for t in db_word.translations if t.language == language), None)

    has_new_audio = audio is not None and audio.filename
    audio_subdir = f"dictionaries/{db_word.dictionary_id}/translation_audio/{language}"

    if existing is None:
        db_translation = WordTranslation(
            word_id=word_id,
            language=language,
            text=text.strip(),
            audio_key=save_upload(audio, subdir=audio_subdir) if has_new_audio else None,
        )
        db.add(db_translation)
    else:
        db_translation = existing
        db_translation.text = text.strip()
        if has_new_audio:
            delete_by_key(db_translation.audio_key)
            db_translation.audio_key = save_upload(audio, subdir=audio_subdir)
        elif remove_audio:
            delete_by_key(db_translation.audio_key)
            db_translation.audio_key = None

    db.commit()
    db.refresh(db_translation)
    return translation_to_out(db_translation)


@router.delete("/words/{word_id}/translations/{language}", status_code=status.HTTP_204_NO_CONTENT)
def delete_translation(
    word_id: int,
    language: str,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    language = language.strip().lower()
    db_word = _get_word_or_404(db, word_id)
    existing = next((t for t in db_word.translations if t.language == language), None)
    if existing is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Translation not found")

    if len(db_word.translations) <= 1:
        # A word with zero translations is a broken state for every reader
        # of this API (the Flutter app included, which expects `translation`
        # to always be a string) -- a word must keep at least one.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Cannot delete the only translation of a word. Add another translation first.",
        )

    delete_by_key(existing.audio_key)
    db.delete(existing)
    db.commit()
    return None
