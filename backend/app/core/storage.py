"""File storage abstraction.

Stores files on local disk under MEDIA_ROOT and returns a "storage key"
(a relative path) that is persisted on the Word row. `url_for_key` turns a
key into a URL the client can fetch.

Keeping this behind a small module means the Word model only ever sees an
opaque key/URL pair -- swapping local disk for S3-compatible object storage
later only requires changing `save_upload` / `url_for_key`, not the schema.
"""
import uuid
from pathlib import Path

from fastapi import UploadFile

from app.config import get_settings

settings = get_settings()

MEDIA_ROOT = Path(settings.media_root)


def _ext_for(upload: UploadFile) -> str:
    suffix = Path(upload.filename or "").suffix
    return suffix if suffix else ""


def save_upload(upload: UploadFile | None, *, subdir: str) -> str | None:
    """Persist an uploaded file, returning its storage key, or None if no file given."""
    if upload is None or not upload.filename:
        return None

    target_dir = MEDIA_ROOT / subdir
    target_dir.mkdir(parents=True, exist_ok=True)

    filename = f"{uuid.uuid4().hex}{_ext_for(upload)}"
    key = f"{subdir}/{filename}"
    dest = MEDIA_ROOT / key

    with dest.open("wb") as f:
        f.write(upload.file.read())

    return key


def delete_by_key(key: str | None) -> None:
    if not key:
        return
    path = MEDIA_ROOT / key
    if path.is_file():
        try:
            path.unlink()
        except OSError:
            pass


def url_for_key(key: str | None) -> str | None:
    if not key:
        return None
    prefix = settings.media_url_prefix.rstrip("/")
    return f"{prefix}/{key}"
