"""GET /admin/backup: the whole database and every media file as one ZIP
(app/backup) -- what the local backup script downloads."""

import datetime as dt

from fastapi import APIRouter, Depends
from fastapi.responses import FileResponse
from starlette.background import BackgroundTask
from sqlalchemy.orm import Session

from app.backup import make_backup, media_index
from app.core.deps import get_current_admin
from app.database import get_db

router = APIRouter(prefix="/admin/backup", tags=["admin-backup"])


@router.get("/media")
def list_media(_admin=Depends(get_current_admin)):
    """Every media file (key, size); each is downloadable at /media/<key>."""
    return media_index()


@router.get("")
def download_backup(media: bool = True, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    path = make_backup(db, include_media=media)
    stamp = dt.datetime.now().strftime("%Y-%m-%d_%H-%M")
    return FileResponse(
        path,
        media_type="application/zip",
        filename=f"guyo-backup_{stamp}.zip",
        background=BackgroundTask(path.unlink),
    )
