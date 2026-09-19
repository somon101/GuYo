import io
import json
import os
import tempfile
import uuid
import zipfile

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, Query, Response, UploadFile, status
from pydantic import ValidationError as PydanticValidationError
from sqlalchemy.orm import Session

from app.core.deps import Principal, get_current_admin, get_current_principal
from app.core.storage import MEDIA_ROOT, delete_by_key, save_bytes, save_upload, url_for_key
from app.database import SessionLocal, get_db
from app.models.dictionary import Dictionary
from app.models.import_job import ImportJob
from app.models.phrase import Phrase, PhraseCategory
from app.routers.words import _add_audio_to_zip, _read_zip_audio
from app.schemas.bulk import (
    ExportPhrase,
    ExportPhraseCategory,
    ExportPhrasePayload,
    ImportJobOut,
    ImportPhrasePayload,
    ImportPhraseSummary,
)
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


def _validate_import_phrase_zip(zf: zipfile.ZipFile, payload: ImportPhrasePayload) -> None:
    """Everything about the phrases ZIP that Pydantic's field types alone
    can't check: each audio/audio_tg path (when present at all -- both
    fields stay fully optional) must actually point at a real entry inside
    this same archive, under the right audio/phrases/original/ or
    audio/phrases/tg/ folder, and never escape the archive via "..".
    Raises ValueError with a specific, human-readable reason (which phrase,
    which category, which field) -- never a generic "invalid format" --
    and runs to completion over the WHOLE payload before the import is
    allowed to touch the database, so a problem anywhere in a large file
    never produces a partial import. Mirrors words.py's
    `_validate_import_zip`."""
    zip_names = set(zf.namelist())
    for cat in payload.categories:
        cat_name = cat.name.strip()
        if not cat_name:
            raise ValueError("Найдена категория с пустым названием.")
        for phrase in cat.phrases:
            sentence = phrase.sentence.strip()
            if not sentence:
                raise ValueError(f"В категории «{cat_name}» найдена фраза с пустым текстом.")
            for field_name, path, expected_prefix in (
                ("audio", phrase.audio, "audio/phrases/original/"),
                ("audio_tg", phrase.audio_tg, "audio/phrases/tg/"),
            ):
                if path is None:
                    continue
                if not path or path.startswith("/") or ".." in path.split("/"):
                    raise ValueError(
                        f"Фраза «{sentence}» ({cat_name}): недопустимый путь в поле {field_name}: {path!r}"
                    )
                if not path.startswith(expected_prefix):
                    raise ValueError(
                        f"Фраза «{sentence}» ({cat_name}): поле {field_name} должно начинаться с "
                        f"{expected_prefix!r}, получено {path!r}"
                    )
                if path not in zip_names:
                    raise ValueError(
                        f"Фраза «{sentence}» ({cat_name}): файл {path!r}, указанный в поле {field_name}, "
                        f"отсутствует в архиве"
                    )


def _open_and_validate_phrase_zip(zip_path: str) -> tuple[zipfile.ZipFile, ImportPhrasePayload]:
    """The full pre-DB validation pass for a phrases ZIP: a real ZIP, a
    phrases.json at its root, valid JSON, the fixed categories/phrases
    shape, and every referenced audio file actually present. Mirrors
    words.py's `_open_and_validate_zip`."""
    try:
        zf = zipfile.ZipFile(zip_path)
    except zipfile.BadZipFile as exc:
        raise ValueError("ZIP-архив повреждён или не является ZIP-файлом.") from exc

    try:
        raw = zf.read("phrases.json")
    except KeyError as exc:
        raise ValueError("В архиве отсутствует файл phrases.json.") from exc

    try:
        payload_data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"phrases.json содержит некорректный JSON: {exc}") from exc

    try:
        payload = ImportPhrasePayload.model_validate(payload_data)
    except PydanticValidationError as exc:
        first = exc.errors()[0]
        loc = ".".join(str(part) for part in first["loc"]) or "categories"
        raise ValueError(f"phrases.json не соответствует формату (поле {loc}): {first['msg']}") from exc

    _validate_import_phrase_zip(zf, payload)
    return zf, payload


def _merge_import_phrase_payload(
    db: Session, dictionary_id: int, zf: zipfile.ZipFile, payload: ImportPhrasePayload
) -> ImportPhraseSummary:
    """The actual merge, run only after `_open_and_validate_phrase_zip`
    already passed: a category already present (matched by name) is reused,
    never duplicated; a phrase already present in that category (matched by
    exact `sentence` text) is reused too -- it's synced, not overwritten:
    its Tajik translation text is refreshed, and audio (original + Tajik
    translation) is added or replaced whenever the ZIP actually references a
    real audio file, but left exactly as-is when it doesn't. Re-importing
    the same file is therefore safe to repeat. Mirrors words.py's
    `_merge_import_payload`."""
    categories_created = categories_reused = 0
    phrases_created = phrases_reused = 0

    for cat_data in payload.categories:
        name = cat_data.name.strip()
        category = (
            db.query(PhraseCategory)
            .filter(PhraseCategory.dictionary_id == dictionary_id, PhraseCategory.name == name)
            .first()
        )
        if category is None:
            category = PhraseCategory(dictionary_id=dictionary_id, name=name)
            db.add(category)
            db.flush()
            categories_created += 1
        else:
            categories_reused += 1

        for phrase_data in cat_data.phrases:
            sentence = phrase_data.sentence.strip()
            db_phrase = (
                db.query(Phrase)
                .filter(
                    Phrase.dictionary_id == dictionary_id,
                    Phrase.category_id == category.id,
                    Phrase.original == sentence,
                )
                .first()
            )
            if db_phrase is None:
                db_phrase = Phrase(
                    dictionary_id=dictionary_id,
                    category_id=category.id,
                    original=sentence,
                    translation_tg=phrase_data.translation_tg.strip(),
                )
                db.add(db_phrase)
                db.flush()
                phrases_created += 1
            else:
                db_phrase.translation_tg = phrase_data.translation_tg.strip()
                phrases_reused += 1

            # Same add-or-replace sync rule as words: real audio in the ZIP
            # always wins (added if there was none, replaced if there
            # already was one); no audio referenced leaves whatever's
            # already there alone.
            audio_bytes = _read_zip_audio(zf, phrase_data.audio)
            if audio_bytes is not None:
                delete_by_key(db_phrase.original_audio_key)
                db_phrase.original_audio_key = save_bytes(
                    audio_bytes,
                    subdir=f"dictionaries/{dictionary_id}/phrase_original_audio",
                    filename_hint=phrase_data.audio,
                )

            audio_tg_bytes = _read_zip_audio(zf, phrase_data.audio_tg)
            if audio_tg_bytes is not None:
                delete_by_key(db_phrase.translation_audio_key)
                db_phrase.translation_audio_key = save_bytes(
                    audio_tg_bytes,
                    subdir=f"dictionaries/{dictionary_id}/phrase_translation_audio",
                    filename_hint=phrase_data.audio_tg,
                )

    return ImportPhraseSummary(
        categories_created=categories_created,
        categories_reused=categories_reused,
        phrases_created=phrases_created,
        phrases_reused=phrases_reused,
    )


def _run_import_phrase_job(job_id: str, dictionary_id: int, zip_path: str) -> None:
    """The actual import work, run entirely outside the HTTP request that
    started it -- same reasoning and shape as words.py's `_run_import_job`:
    its own DB session, no FastAPI Depends() involved, keeps going (and
    stays retrievable by job_id) no matter what Admin Web's browser does in
    the meantime."""
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

            zf, payload = _open_and_validate_phrase_zip(zip_path)
            try:
                summary = _merge_import_phrase_payload(db, dictionary_id, zf, payload)
                db.commit()
            finally:
                zf.close()

            job = db.get(ImportJob, job_id)
            job.status = "completed"
            job.categories_created = summary.categories_created
            job.categories_reused = summary.categories_reused
            job.phrases_created = summary.phrases_created
            job.phrases_reused = summary.phrases_reused
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
    "/dictionaries/{dictionary_id}/phrases/import",
    response_model=ImportJobOut,
    status_code=status.HTTP_202_ACCEPTED,
)
def import_phrases(
    dictionary_id: int,
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Starts a phrases ZIP import as a server-tracked background job -- the
    phrase counterpart of import_words in words.py, same shape: Admin Web
    only uploads the file and gets back a job_id; the actual parsing,
    validation and database merge happen in `_run_import_phrase_job` after
    this request already returned. Polling GET
    .../phrases/import/{job_id} is the only way the result is meant to be
    observed."""
    _get_dictionary_or_404(db, dictionary_id)

    with tempfile.NamedTemporaryFile(delete=False, suffix=".zip") as tmp:
        tmp.write(file.file.read())
        zip_path = tmp.name

    job = ImportJob(id=uuid.uuid4().hex, dictionary_id=dictionary_id, status="pending")
    db.add(job)
    db.commit()

    background_tasks.add_task(_run_import_phrase_job, job.id, dictionary_id, zip_path)

    return ImportJobOut(job_id=job.id, status=job.status)


@router.get("/dictionaries/{dictionary_id}/phrases/import/{job_id}", response_model=ImportJobOut)
def get_phrase_import_job(
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
        phrases_created=job.phrases_created,
        phrases_reused=job.phrases_reused,
    )


@router.get("/dictionaries/{dictionary_id}/phrases/export")
def export_phrases(
    dictionary_id: int,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """The exact inverse of import_phrases: a ZIP archive containing
    phrases.json (same fixed categories/phrases shape, plus this phrase's
    own and Tajik-translation audio paths when they exist) and the
    referenced audio files themselves under audio/phrases/original/ and
    audio/phrases/tg/ -- the result can be fed straight back into import.
    Phrases with no category are grouped under a plain "Без категории"
    category, same convention as export_words."""
    _get_dictionary_or_404(db, dictionary_id)

    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zf:

        def phrase_out(p: Phrase) -> ExportPhrase:
            return ExportPhrase(
                sentence=p.original,
                translation_tg=p.translation_tg,
                audio=_add_audio_to_zip(zf, p.original_audio_key, "audio/phrases/original"),
                audio_tg=_add_audio_to_zip(zf, p.translation_audio_key, "audio/phrases/tg"),
            )

        categories = (
            db.query(PhraseCategory)
            .filter(PhraseCategory.dictionary_id == dictionary_id)
            .order_by(PhraseCategory.id)
            .all()
        )
        result = [
            ExportPhraseCategory(
                name=cat.name,
                phrases=[
                    phrase_out(p)
                    for p in db.query(Phrase).filter(Phrase.category_id == cat.id).order_by(Phrase.id).all()
                ],
            )
            for cat in categories
        ]

        uncategorized = (
            db.query(Phrase)
            .filter(Phrase.dictionary_id == dictionary_id, Phrase.category_id.is_(None))
            .order_by(Phrase.id)
            .all()
        )
        if uncategorized:
            result.append(ExportPhraseCategory(name="Без категории", phrases=[phrase_out(p) for p in uncategorized]))

        payload = ExportPhrasePayload(categories=result)
        zf.writestr("phrases.json", payload.model_dump_json(indent=2))

    return Response(
        content=zip_buffer.getvalue(),
        media_type="application/zip",
        headers={"Content-Disposition": 'attachment; filename="phrases.zip"'},
    )
