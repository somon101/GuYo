import io
import json
import os
import tempfile
import uuid
import zipfile

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, Query, Response, UploadFile, status
from pydantic import ValidationError as PydanticValidationError
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.deps import Principal, get_current_admin, get_current_principal
from app.core.languages import is_valid_translation_language
from app.core.storage import MEDIA_ROOT, delete_by_key, save_bytes, save_upload, url_for_key
from app.database import SessionLocal, get_db
from app.exercises.common import fill_word_progress
from app.models.category import Category
from app.models.dictionary import Dictionary
from app.models.import_job import ImportJob
from app.models.word import Word, WordForm, WordTranslation
from app.schemas.bulk import (
    ExportCategory,
    ExportPayload,
    ExportWord,
    ImportJobOut,
    ImportPayload,
    ImportSummary,
)
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
    out = [word_to_out(w) for w in words]
    # A logged-in user also gets their OWN progress on each word (score, and
    # which reinforcement level that score falls into), so the shared word
    # card shows the same status pill here as it does in "Мои слова". An
    # admin has no per-word progress of their own, so these stay null.
    if principal.role == "user":
        fill_word_progress(db, principal.id, out, [w.id for w in words])
    return out


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


def _get_or_create_category(db: Session, dictionary_id: int, name: str) -> tuple[Category, bool]:
    """Two ZIP imports of the same file hitting the backend close together
    (e.g. a slow multi-MB upload retried, or an impatient second click)
    would otherwise both see no existing category, both try to insert it,
    and the loser would crash the whole import on the (dictionary_id, name)
    unique constraint. A SAVEPOINT here means that race just falls back to
    "someone else already created it" instead of a 500."""
    category = db.query(Category).filter(Category.dictionary_id == dictionary_id, Category.name == name).first()
    if category is not None:
        return category, False
    try:
        with db.begin_nested():
            category = Category(dictionary_id=dictionary_id, name=name)
            db.add(category)
            db.flush()
        return category, True
    except IntegrityError:
        category = db.query(Category).filter(Category.dictionary_id == dictionary_id, Category.name == name).first()
        return category, False  # type: ignore[return-value]


def _read_zip_audio(zf: zipfile.ZipFile, path: str | None) -> bytes | None:
    """Reads one audio entry out of the dictionary ZIP by the relative path
    given in dictionary.json. By the time this runs, `_validate_import_zip`
    has already confirmed the path exists (when one was given at all), so
    a missing entry here only means the field itself was absent/null --
    reading nothing is the correct outcome, not an error."""
    if not path:
        return None
    try:
        return zf.read(path)
    except KeyError:
        return None


def _validate_import_zip(zf: zipfile.ZipFile, payload: ImportPayload) -> None:
    """Everything about the ZIP that Pydantic's field types alone can't
    check: each audio/audio_tg path (when present at all -- both fields
    stay fully optional) must actually point at a real entry inside this
    same archive, under the right audio/original/ or audio/tg/ folder, and
    never escape the archive via "..". Raises ValueError with a specific,
    human-readable reason (which word, which category, which field) --
    never a generic "invalid format" -- and runs to completion over the
    WHOLE payload before the import is allowed to touch the database, so a
    problem anywhere in a large file never produces a partial import."""
    zip_names = set(zf.namelist())
    for cat in payload.categories:
        cat_name = cat.name.strip()
        if not cat_name:
            raise ValueError("Найдена категория с пустым названием.")
        for word in cat.words:
            word_text = word.word.strip()
            if not word_text:
                raise ValueError(f"В категории «{cat_name}» найдено слово с пустым текстом.")
            for field_name, path, expected_prefix in (
                ("audio", word.audio, "audio/original/"),
                ("audio_tg", word.audio_tg, "audio/tg/"),
            ):
                if path is None:
                    continue
                if not path or path.startswith("/") or ".." in path.split("/"):
                    raise ValueError(
                        f"Слово «{word_text}» ({cat_name}): недопустимый путь в поле {field_name}: {path!r}"
                    )
                if not path.startswith(expected_prefix):
                    raise ValueError(
                        f"Слово «{word_text}» ({cat_name}): поле {field_name} должно начинаться с "
                        f"{expected_prefix!r}, получено {path!r}"
                    )
                if path not in zip_names:
                    raise ValueError(
                        f"Слово «{word_text}» ({cat_name}): файл {path!r}, указанный в поле {field_name}, "
                        f"отсутствует в архиве"
                    )


def _open_and_validate_zip(zip_path: str) -> tuple[zipfile.ZipFile, ImportPayload]:
    """The full pre-DB validation pass: a real ZIP, a dictionary.json at its
    root, valid JSON, the fixed categories/words shape, and every
    referenced audio file actually present. Raises ValueError with a
    specific reason on the first problem found; the caller must not touch
    the database unless this returns successfully."""
    try:
        zf = zipfile.ZipFile(zip_path)
    except zipfile.BadZipFile as exc:
        raise ValueError("ZIP-архив повреждён или не является ZIP-файлом.") from exc

    try:
        raw = zf.read("dictionary.json")
    except KeyError as exc:
        raise ValueError("В архиве отсутствует файл dictionary.json.") from exc

    try:
        payload_data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"dictionary.json содержит некорректный JSON: {exc}") from exc

    try:
        payload = ImportPayload.model_validate(payload_data)
    except PydanticValidationError as exc:
        first = exc.errors()[0]
        loc = ".".join(str(part) for part in first["loc"]) or "categories"
        raise ValueError(f"dictionary.json не соответствует формату (поле {loc}): {first['msg']}") from exc

    _validate_import_zip(zf, payload)
    return zf, payload


def _merge_import_payload(
    db: Session, dictionary: Dictionary, zf: zipfile.ZipFile, payload: ImportPayload
) -> ImportSummary:
    """The actual merge, run only after `_open_and_validate_zip` already
    passed: a category already present (matched by name) is reused, never
    duplicated; a word already present in that category (matched by exact
    word text) is reused too -- it's synced, not overwritten: its Tajik
    translation text is refreshed, any forms not already there (exact text
    match, per language) are appended (existing forms are never removed
    just because this file doesn't list them), and audio (word + Tajik
    translation) is added or replaced whenever the ZIP actually references
    a real audio file, but left exactly as-is when it doesn't. Re-importing
    the same file is therefore safe to repeat. Only genuinely new words get
    a new word_id."""
    dictionary_id = dictionary.id
    categories_created = categories_reused = 0
    words_created = words_reused = 0
    forms_added = 0

    for cat_data in payload.categories:
        name = cat_data.name.strip()
        category, was_created = _get_or_create_category(db, dictionary_id, name)
        if was_created:
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

            # The word's own pronunciation, in the dictionary's own
            # language. A ZIP that references real audio always wins (added
            # if there was none, replaced if there already was one); a ZIP
            # with no audio for this word (missing field, or null) leaves
            # whatever audio is already there alone -- sync never deletes
            # data the new file is simply silent about.
            audio_bytes = _read_zip_audio(zf, word_data.audio)
            if audio_bytes is not None:
                delete_by_key(db_word.word_audio_key)
                db_word.word_audio_key = save_bytes(
                    audio_bytes,
                    subdir=f"dictionaries/{dictionary_id}/word_audio",
                    filename_hint=word_data.audio,
                )

            translation_text = word_data.translation_tg.strip()
            existing_translation = next((t for t in db_word.translations if t.language == "tg"), None)
            if translation_text:
                if existing_translation is None:
                    existing_translation = WordTranslation(word_id=db_word.id, language="tg", text=translation_text)
                    db.add(existing_translation)
                else:
                    existing_translation.text = translation_text

            # The Tajik translation's own pronunciation -- attaches only to
            # an actual "tg" translation row. Same add-or-replace sync rule
            # as the word's own audio above: real audio in the ZIP always
            # wins, no audio referenced leaves the existing one alone.
            if existing_translation is not None:
                audio_tg_bytes = _read_zip_audio(zf, word_data.audio_tg)
                if audio_tg_bytes is not None:
                    delete_by_key(existing_translation.audio_key)
                    existing_translation.audio_key = save_bytes(
                        audio_tg_bytes,
                        subdir=f"dictionaries/{dictionary_id}/translation_audio/tg",
                        filename_hint=word_data.audio_tg,
                    )

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

    return ImportSummary(
        categories_created=categories_created,
        categories_reused=categories_reused,
        words_created=words_created,
        words_reused=words_reused,
        forms_added=forms_added,
    )


def _run_import_job(job_id: str, dictionary_id: int, zip_path: str) -> None:
    """The actual import work, run entirely outside the HTTP request that
    started it: its own DB session (never the request's -- that one is
    closed by the time a background task runs), no FastAPI Depends()
    involved. This keeps going, and its result stays retrievable by
    job_id, no matter whether the admin's browser is still connected,
    still on this page, or closed entirely -- Admin Web only ever polls
    GET .../import/{job_id} for whatever this last wrote."""
    db = SessionLocal()
    try:
        job = db.get(ImportJob, job_id)
        if job is None:
            return
        job.status = "processing"
        db.commit()

        try:
            dictionary = db.get(Dictionary, dictionary_id)
            if dictionary is None:
                raise ValueError("Словарь не найден.")

            zf, payload = _open_and_validate_zip(zip_path)
            try:
                summary = _merge_import_payload(db, dictionary, zf, payload)
                db.commit()
            finally:
                zf.close()

            job = db.get(ImportJob, job_id)
            job.status = "completed"
            job.categories_created = summary.categories_created
            job.categories_reused = summary.categories_reused
            job.words_created = summary.words_created
            job.words_reused = summary.words_reused
            job.forms_added = summary.forms_added
            db.commit()
        except ValueError as exc:
            db.rollback()
            job = db.get(ImportJob, job_id)
            job.status = "failed"
            job.error_message = str(exc)
            db.commit()
        except Exception as exc:  # noqa: BLE001 -- an import job must always reach a terminal state
            db.rollback()
            job = db.get(ImportJob, job_id)
            job.status = "failed"
            job.error_message = f"Непредвиденная ошибка при импорте: {exc}"
            db.commit()
    finally:
        db.close()
        try:
            os.remove(zip_path)
        except OSError:
            pass


@router.post(
    "/dictionaries/{dictionary_id}/import",
    response_model=ImportJobOut,
    status_code=status.HTTP_202_ACCEPTED,
)
def import_words(
    dictionary_id: int,
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Starts a dictionary ZIP import as a server-tracked background job.
    Admin Web only uploads the file and gets back a job_id; the actual
    parsing, validation and database merge happen in `_run_import_job`
    after this request already returned, so a slow upload/large archive
    keeps being processed here even if the admin navigates away or closes
    the tab -- polling GET .../import/{job_id} is the only way the result
    is meant to be observed, never a state held only in the browser."""
    dictionary = _get_dictionary_or_404(db, dictionary_id)
    _require_valid_language(dictionary.language)

    with tempfile.NamedTemporaryFile(delete=False, suffix=".zip") as tmp:
        tmp.write(file.file.read())
        zip_path = tmp.name

    job = ImportJob(id=uuid.uuid4().hex, dictionary_id=dictionary_id, status="pending")
    db.add(job)
    db.commit()

    background_tasks.add_task(_run_import_job, job.id, dictionary_id, zip_path)

    return ImportJobOut(job_id=job.id, status=job.status)


@router.get("/dictionaries/{dictionary_id}/import/{job_id}", response_model=ImportJobOut)
def get_import_job(
    dictionary_id: int,
    job_id: str,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    job = db.get(ImportJob, job_id)
    if job is None or job.dictionary_id != dictionary_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Import job not found")
    return ImportJobOut(
        job_id=job.id,
        status=job.status,
        error_message=job.error_message,
        categories_created=job.categories_created,
        categories_reused=job.categories_reused,
        words_created=job.words_created,
        words_reused=job.words_reused,
        forms_added=job.forms_added,
    )


def _add_audio_to_zip(zf: zipfile.ZipFile, storage_key: str | None, zip_subdir: str) -> str | None:
    """Copies one already-stored audio file (by its storage key) into the
    export ZIP under `zip_subdir` ("audio/original" or "audio/tg"),
    returning the path to reference from dictionary.json -- or None if
    there's no audio, or the file is somehow missing from disk. The
    storage key's own filename (already a unique uuid4-based name, see
    app.core.storage) is reused as the ZIP entry name, so it can never
    collide with another word's audio in the same archive."""
    if not storage_key:
        return None
    file_path = MEDIA_ROOT / storage_key
    if not file_path.is_file():
        return None
    entry_name = f"{zip_subdir}/{file_path.name}"
    zf.write(file_path, entry_name)
    return entry_name


@router.get("/dictionaries/{dictionary_id}/export")
def export_words(
    dictionary_id: int,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """The exact inverse of import: a ZIP archive containing dictionary.json
    (same fixed categories/words shape, plus this word's own-language and
    Tajik-translation audio paths when they exist) and the referenced audio
    files themselves under audio/original/ and audio/tg/ -- the result can
    be fed straight back into import. Words with no category are grouped
    under a plain "Без категории" category, which round-trips like any
    other named category on the next import."""
    dictionary = _get_dictionary_or_404(db, dictionary_id)

    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zf:

        def word_out(w: Word) -> ExportWord:
            tg_translation = next((t for t in w.translations if t.language == "tg"), None)
            return ExportWord(
                word=w.word,
                translation_tg=tg_translation.text if tg_translation is not None else "",
                forms=[f.text for f in w.forms if f.language == dictionary.language],
                forms_tg=[f.text for f in w.forms if f.language == "tg"],
                audio=_add_audio_to_zip(zf, w.word_audio_key, "audio/original"),
                audio_tg=_add_audio_to_zip(
                    zf, tg_translation.audio_key if tg_translation is not None else None, "audio/tg"
                ),
            )

        categories = db.query(Category).filter(Category.dictionary_id == dictionary_id).order_by(Category.id).all()
        result = [
            ExportCategory(
                name=cat.name,
                words=[
                    word_out(w) for w in db.query(Word).filter(Word.category_id == cat.id).order_by(Word.id).all()
                ],
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

        payload = ExportPayload(categories=result)
        zf.writestr("dictionary.json", payload.model_dump_json(indent=2))

    return Response(
        content=zip_buffer.getvalue(),
        media_type="application/zip",
        headers={"Content-Disposition": 'attachment; filename="dictionary.zip"'},
    )
