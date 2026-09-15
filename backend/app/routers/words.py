from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile, status
from sqlalchemy.orm import Session

from app.core.deps import Principal, get_current_admin, get_current_principal
from app.core.languages import is_valid_translation_language
from app.core.storage import delete_by_key, save_upload, url_for_key
from app.database import get_db
from app.models.category import Category
from app.models.dictionary import Dictionary
from app.models.word import Word, WordForm, WordTranslation
from app.schemas.bulk import ExportCategory, ExportPayload, ExportWord, ImportPayload, ImportSummary
from app.schemas.word import WordFormOut, WordOut, WordTranslationOut

router = APIRouter(tags=["words"])


def _default_translation_language(dictionary_language: str) -> str:
    """A word's translation language was never asked for explicitly before
    this stage. Default it the same way the data migration inferred it for
    existing rows: Russian, unless the dictionary itself is Russian, in
    which case English."""
    return "en" if dictionary_language == "ru" else "ru"


def translation_to_out(t: WordTranslation) -> WordTranslationOut:
    return WordTranslationOut(id=t.id, language=t.language, text=t.text, audio_url=url_for_key(t.audio_key))


def form_to_out(f: WordForm) -> WordFormOut:
    return WordFormOut(id=f.id, language=f.language, text=f.text)


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
        category_id=word.category_id,
        category_name=word.category.name if word.category is not None else None,
        created_at=word.created_at,
        updated_at=word.updated_at,
        translation=primary.text if primary else None,
        translation_audio_url=primary.audio_url if primary else None,
        translations=translations,
        forms=[form_to_out(f) for f in word.forms],
    )


def _get_dictionary_or_404(
    db: Session, dictionary_id: int, principal: Principal | None = None
) -> Dictionary:
    dictionary = db.get(Dictionary, dictionary_id)
    if dictionary is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")
    # A draft dictionary -- and therefore every Word in it -- is invisible
    # to anyone but an admin. Reported as a plain 404, same as "doesn't
    # exist", so a regular user can't even tell a draft is there.
    if principal is not None and principal.role != "admin" and not dictionary.is_published:
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


def _resolve_category(db: Session, dictionary_id: int, category_id: int | None) -> Category | None:
    """A word's category (if any) must belong to the SAME dictionary -- a
    word can't be filed under a category that lives in a different
    language's block."""
    if category_id is None:
        return None
    category = db.get(Category, category_id)
    if category is None or category.dictionary_id != dictionary_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found in this dictionary")
    return category


@router.get("/dictionaries/{dictionary_id}/words", response_model=list[WordOut])
def list_words(
    dictionary_id: int,
    category_id: int | None = Query(None, description="Filter to a single category; omit for all words."),
    db: Session = Depends(get_db),
    principal: Principal = Depends(get_current_principal),
):
    _get_dictionary_or_404(db, dictionary_id, principal)
    query = db.query(Word).filter(Word.dictionary_id == dictionary_id)
    if category_id is not None:
        query = query.filter(Word.category_id == category_id)
    words = query.order_by(Word.id).all()
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
    category_id: int | None = Form(None),
    word_audio: UploadFile | None = File(None),
    translation_audio: UploadFile | None = File(None),
    image: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    dictionary = _get_dictionary_or_404(db, dictionary_id)
    category = _resolve_category(db, dictionary_id, category_id)

    lang = (translation_language or _default_translation_language(dictionary.language)).strip().lower()
    _require_valid_language(lang)

    transcription = transcription.strip() if transcription and transcription.strip() else None

    db_word = Word(
        dictionary_id=dictionary_id,
        category_id=category.id if category else None,
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
def get_word(
    word_id: int, db: Session = Depends(get_db), principal: Principal = Depends(get_current_principal)
):
    db_word = _get_word_or_404(db, word_id)
    _get_dictionary_or_404(db, db_word.dictionary_id, principal)
    return word_to_out(db_word)


@router.patch("/words/{word_id}", response_model=WordOut)
def update_word(
    word_id: int,
    word: str | None = Form(None),
    transcription: str | None = Form(None),
    remove_transcription: bool = Form(False),
    category_id: int | None = Form(None),
    remove_category: bool = Form(False),
    word_audio: UploadFile | None = File(None),
    remove_word_audio: bool = Form(False),
    image: UploadFile | None = File(None),
    remove_image: bool = Form(False),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Updates the Word itself: its text, transcription, own pronunciation,
    image and category. Never touches other words, and changing one field
    here never clears the others -- each field/file is only replaced or
    removed when explicitly asked for. Translations and Forms are managed
    through their own dedicated endpoints below."""
    db_word = _get_word_or_404(db, word_id)

    if word is not None and word.strip():
        db_word.word = word.strip()

    if remove_transcription:
        db_word.transcription = None
    elif transcription is not None and transcription.strip():
        db_word.transcription = transcription.strip()

    if remove_category:
        db_word.category_id = None
    elif category_id is not None:
        category = _resolve_category(db, db_word.dictionary_id, category_id)
        db_word.category_id = category.id if category else None

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


@router.post("/words/{word_id}/forms", response_model=WordFormOut, status_code=status.HTTP_201_CREATED)
def add_form(
    word_id: int,
    language: str = Form(...),
    text: str = Form(..., min_length=1, max_length=255),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Appends one more grammatical form of this word, in `language`. Unlike
    translations, a word can have any number of forms in the same
    language -- this always adds a new row, never overwrites an existing
    one. Order is preserved as insertion order (ascending id)."""
    language = language.strip().lower()
    _require_valid_language(language)
    _get_word_or_404(db, word_id)

    db_form = WordForm(word_id=word_id, language=language, text=text.strip())
    db.add(db_form)
    db.commit()
    db.refresh(db_form)
    return form_to_out(db_form)


@router.delete("/words/{word_id}/forms/{form_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_form(
    word_id: int,
    form_id: int,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    db_form = db.get(WordForm, form_id)
    if db_form is None or db_form.word_id != word_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Form not found")

    db.delete(db_form)
    db.commit()
    return None


@router.post("/dictionaries/{dictionary_id}/import", response_model=ImportSummary)
def import_words(
    dictionary_id: int,
    payload: ImportPayload,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Bulk-loads words from the fixed categories/words JSON format (see
    ExportPayload, the exact same shape). A category already present
    (matched by name) is reused, never duplicated; a word already present
    in that category (matched by exact word text) is reused too -- its
    Tajik translation is refreshed and any forms not already there (exact
    text match, per language) are appended. Re-importing the same file is
    therefore safe to repeat. Only genuinely new words get a new word_id."""
    dictionary = _get_dictionary_or_404(db, dictionary_id)
    _require_valid_language(dictionary.language)

    categories_created = categories_reused = 0
    words_created = words_reused = 0
    forms_added = 0

    for cat_data in payload.categories:
        name = cat_data.name.strip()
        category = (
            db.query(Category)
            .filter(Category.dictionary_id == dictionary_id, Category.name == name)
            .first()
        )
        if category is None:
            category = Category(dictionary_id=dictionary_id, name=name)
            db.add(category)
            db.flush()
            categories_created += 1
        else:
            categories_reused += 1

        for word_data in cat_data.words:
            word_text = word_data.word.strip()
            db_word = (
                db.query(Word)
                .filter(
                    Word.dictionary_id == dictionary_id,
                    Word.category_id == category.id,
                    Word.word == word_text,
                )
                .first()
            )
            if db_word is None:
                db_word = Word(dictionary_id=dictionary_id, category_id=category.id, word=word_text)
                db.add(db_word)
                db.flush()
                words_created += 1
            else:
                words_reused += 1

            translation_text = word_data.translation_tg.strip()
            if translation_text:
                existing_translation = next((t for t in db_word.translations if t.language == "tg"), None)
                if existing_translation is None:
                    db.add(WordTranslation(word_id=db_word.id, language="tg", text=translation_text))
                else:
                    existing_translation.text = translation_text

            existing_main_forms = {f.text for f in db_word.forms if f.language == dictionary.language}
            for form_text in word_data.forms:
                text = form_text.strip()
                if text and text not in existing_main_forms:
                    db.add(WordForm(word_id=db_word.id, language=dictionary.language, text=text))
                    existing_main_forms.add(text)
                    forms_added += 1

            existing_tg_forms = {f.text for f in db_word.forms if f.language == "tg"}
            for form_text in word_data.forms_tg:
                text = form_text.strip()
                if text and text not in existing_tg_forms:
                    db.add(WordForm(word_id=db_word.id, language="tg", text=text))
                    existing_tg_forms.add(text)
                    forms_added += 1

    db.commit()
    return ImportSummary(
        categories_created=categories_created,
        categories_reused=categories_reused,
        words_created=words_created,
        words_reused=words_reused,
        forms_added=forms_added,
    )


@router.get("/dictionaries/{dictionary_id}/export", response_model=ExportPayload)
def export_words(
    dictionary_id: int,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """The exact inverse of import, in the same fixed JSON shape -- the
    result can be fed straight back into import. Words with no category
    are grouped under a plain "Без категории" category, which round-trips
    like any other named category on the next import."""
    dictionary = _get_dictionary_or_404(db, dictionary_id)

    def word_out(w: Word) -> ExportWord:
        tg_translation = next((t.text for t in w.translations if t.language == "tg"), "")
        return ExportWord(
            word=w.word,
            translation_tg=tg_translation,
            forms=[f.text for f in w.forms if f.language == dictionary.language],
            forms_tg=[f.text for f in w.forms if f.language == "tg"],
        )

    categories = db.query(Category).filter(Category.dictionary_id == dictionary_id).order_by(Category.id).all()
    result = [
        ExportCategory(
            name=cat.name,
            words=[word_out(w) for w in db.query(Word).filter(Word.category_id == cat.id).order_by(Word.id).all()],
        )
        for cat in categories
    ]

    uncategorized = (
        db.query(Word)
        .filter(Word.dictionary_id == dictionary_id, Word.category_id.is_(None))
        .order_by(Word.id)
        .all()
    )
    if uncategorized:
        result.append(ExportCategory(name="Без категории", words=[word_out(w) for w in uncategorized]))

    return ExportPayload(categories=result)
