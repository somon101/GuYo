"""The catalog of frames, badges and titles (pictures the admin uploads) and the
public route that serves them."""

from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, Response, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin
from app.core.storage import MEDIA_ROOT, delete_by_key, save_upload
from app.database import get_db
from app.models.season_pass import CosmeticDef, UserCosmetic

BUILTIN_DIR = Path(__file__).resolve().parent.parent / "assets" / "cosmetics"
KINDS = ("frame", "badge", "title")

router = APIRouter(tags=["cosmetics"])
admin_router = APIRouter(prefix="/admin/cosmetics", tags=["admin-cosmetics"])


def _out(d: CosmeticDef) -> dict:
    return {"id": d.id, "kind": d.kind, "name": d.name, "name_tg": d.name_tg, "name_uz": d.name_uz}


@router.get("/cosmetics/art/{def_id}")
def art(def_id: int, db: Session = Depends(get_db)):
    """The picture of one catalog item (public: it is only artwork)."""
    d = db.get(CosmeticDef, def_id)
    if d is None:
        raise HTTPException(status_code=404, detail="Нет такой картинки")
    path = BUILTIN_DIR / d.image_key.removeprefix("builtin/") if d.image_key.startswith("builtin/") else MEDIA_ROOT / d.image_key
    if not path.is_file():
        raise HTTPException(status_code=404, detail="Нет такой картинки")
    return FileResponse(path, media_type="image/png", headers={"Cache-Control": "public, max-age=3600"})


@admin_router.get("")
def list_defs(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    return [_out(d) for d in db.query(CosmeticDef).order_by(CosmeticDef.kind, CosmeticDef.id).all()]


@admin_router.post("", status_code=status.HTTP_201_CREATED)
def create_def(
    kind: str = Form(...),
    name: str = Form(..., min_length=1, max_length=120),
    name_tg: str = Form(""),
    name_uz: str = Form(""),
    image: UploadFile = File(...),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    if kind not in KINDS:
        raise HTTPException(status_code=422, detail="Тип: рамка, значок или титул")
    if not (image.content_type or "").startswith("image/png"):
        raise HTTPException(status_code=422, detail="Нужна картинка PNG с прозрачным фоном")
    key = save_upload(image, subdir="cosmetics")
    d = CosmeticDef(kind=kind, name=name.strip(), name_tg=name_tg.strip() or None, name_uz=name_uz.strip() or None, image_key=key)
    db.add(d)
    db.commit()
    return _out(d)


@admin_router.put("/{def_id}")
def update_def(
    def_id: int,
    name: str = Form(..., min_length=1, max_length=120),
    name_tg: str = Form(""),
    name_uz: str = Form(""),
    image: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    d = db.get(CosmeticDef, def_id)
    if d is None:
        raise HTTPException(status_code=404, detail="Нет такого элемента")
    d.name, d.name_tg, d.name_uz = name.strip(), name_tg.strip() or None, name_uz.strip() or None
    if image is not None and image.filename:
        if not (image.content_type or "").startswith("image/png"):
            raise HTTPException(status_code=422, detail="Нужна картинка PNG с прозрачным фоном")
        old = d.image_key
        d.image_key = save_upload(image, subdir="cosmetics")
        if not old.startswith("builtin/"):
            delete_by_key(old)
    db.commit()
    return _out(d)


@admin_router.delete("/{def_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_def(def_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    d = db.get(CosmeticDef, def_id)
    if d is None:
        raise HTTPException(status_code=404, detail="Нет такого элемента")
    if db.query(UserCosmetic.id).filter(UserCosmetic.kind == d.kind, UserCosmetic.key == str(d.id)).first():
        raise HTTPException(status_code=409, detail="Это уже получили игроки, удалить нельзя")
    if not d.image_key.startswith("builtin/"):
        delete_by_key(d.image_key)
    db.delete(d)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
