"""Avatar built from parts.

- Admin (/admin/avatar): upload the file "Выгрузить для GuYo" from the Avatar Studio (format
  "avatar-items/1"), see the sets and parts with their IDs and versions, switch a part on or off.
  The admin builds nothing here: every place comes from the Studio.
- App (/avatar/catalog): what the phone downloads, step by step, to show the editor.
- App (PUT /users/me/avatar-look): the finished picture (PNG) plus the choice behind it.
"""

import base64
import hashlib
import json

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin, get_current_user
from app.core.storage import delete_by_key, save_bytes, url_for_key
from app.database import get_db
from app.models.avatar import AvatarBackground, AvatarItem, AvatarMeta
from app.models.user import User

router = APIRouter(tags=["avatar"])
admin_router = APIRouter(prefix="/admin/avatar", tags=["admin-avatar"])

FORMAT = "avatar-items/1"
MAX_IMPORT_BYTES = 120 * 1024 * 1024
MAX_PART_BYTES = 6 * 1024 * 1024
MAX_AVATAR_BYTES = 1024 * 1024
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
GENDERS = ("male", "female")


def _png(data: bytes, what: str) -> bytes:
    if not data.startswith(PNG_MAGIC):
        raise HTTPException(status_code=422, detail=f"{what}: нужна картинка PNG")
    if len(data) > MAX_PART_BYTES:
        raise HTTPException(status_code=422, detail=f"{what}: картинка слишком большая")
    return data


def _meta(db: Session) -> AvatarMeta:
    meta = db.get(AvatarMeta, 1)
    if meta is None:
        meta = AvatarMeta(id=1, canvas={"w": 1200, "h": 1600}, frame=None, slots=[], version=1)
        db.add(meta)
        db.flush()
    return meta


def _place(p: dict) -> dict:
    try:
        return {"x": float(p["x"]), "y": float(p["y"]), "w": float(p["w"]), "r": float(p.get("r", 0)), "pivot": str(p.get("pivot", "center"))}
    except (KeyError, TypeError, ValueError):
        raise HTTPException(status_code=422, detail="В файле у детали неверное положение")


# ---------------------------------------------------------------------------- admin


class ImportReport(BaseModel):
    version: int
    added: int
    updated: int
    unchanged: int
    backgrounds_added: int
    backgrounds_updated: int
    missing_in_file: int  # parts on the server that this file does not contain (kept, not deleted)


@admin_router.post("/import", response_model=ImportReport)
def import_from_studio(file: UploadFile = File(...), db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Takes the Studio's file. The same ID updates the part (its picture and place), a new ID adds one.
    Parts the file does not contain stay as they are (nothing is deleted by an upload)."""
    raw = file.file.read(MAX_IMPORT_BYTES + 1)
    if len(raw) > MAX_IMPORT_BYTES:
        raise HTTPException(status_code=413, detail="Файл слишком большой")
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        raise HTTPException(status_code=422, detail="Это не файл из Студии аватаров")
    if not isinstance(data, dict) or data.get("format") != FORMAT or not isinstance(data.get("items"), list):
        raise HTTPException(status_code=422, detail="Нужен файл «Выгрузить для GuYo» из Студии аватаров")

    added = updated = unchanged = 0
    seen: set[str] = set()
    slots_order = {s["id"]: i for i, s in enumerate(data.get("slots") or []) if isinstance(s, dict) and "id" in s}
    for n, it in enumerate(data["items"]):
        if not isinstance(it, dict) or not it.get("id") or not it.get("slot"):
            raise HTTPException(status_code=422, detail="В файле у детали нет ID или слота")
        item_id = str(it["id"])[:64]
        gender = it.get("gender")
        if gender not in ("male", "female", "both"):
            raise HTTPException(status_code=422, detail="В файле у детали неверный пол")
        place = {g: _place(p) for g, p in (it.get("place") or {}).items() if g in GENDERS}
        if not place:
            raise HTTPException(status_code=422, detail=f"У детали «{it.get('name', item_id)}» нет положения")
        try:
            png = _png(base64.b64decode(it.get("png") or ""), f"Деталь «{it.get('name', item_id)}»")
        except ValueError:
            raise HTTPException(status_code=422, detail="В файле повреждена картинка")
        digest = hashlib.sha1(png).hexdigest()
        row = db.get(AvatarItem, item_id)
        set_info = it.get("set") or {}
        fields = dict(
            slot=str(it["slot"])[:32],
            gender=gender,
            name=str(it.get("name") or "")[:200],
            set_id=str(set_info.get("id") or "")[:64],
            set_name=str(set_info.get("name") or "")[:200],
            width=int(it.get("width") or 0),
            height=int(it.get("height") or 0),
            place=place,
            own_place=bool(it.get("ownPlace")),
            sort=slots_order.get(it["slot"], 99) * 1000 + n,
        )
        seen.add(item_id)
        if row is None:
            key = save_bytes(png, subdir="avatar/items", filename_hint="part.png")
            db.add(AvatarItem(id=item_id, image_key=key, image_hash=digest, **fields))
            added += 1
            continue
        changed = digest != row.image_hash or any(getattr(row, k) != v for k, v in fields.items() if k != "sort")
        if digest != row.image_hash:
            old = row.image_key
            row.image_key = save_bytes(png, subdir="avatar/items", filename_hint="part.png")
            row.image_hash = digest
            delete_by_key(old)
        for k, v in fields.items():
            setattr(row, k, v)
        if changed:
            row.version += 1
            updated += 1
        else:
            unchanged += 1

    bg_added = bg_updated = 0
    for n, b in enumerate(data.get("backgrounds") or []):
        if not isinstance(b, dict) or not b.get("id") or b.get("kind") not in ("solid", "grad", "img"):
            continue
        bid = str(b["id"])[:64]
        png = None
        digest = ""
        if b["kind"] == "img":
            try:
                png = _png(base64.b64decode(b.get("png") or ""), f"Фон «{b.get('name', bid)}»")
            except ValueError:
                raise HTTPException(status_code=422, detail="В файле повреждена картинка фона")
            digest = hashlib.sha1(png).hexdigest()
        row = db.get(AvatarBackground, bid)
        fields = dict(name=str(b.get("name") or "")[:200], kind=b["kind"], c1=b.get("c1"), c2=b.get("c2"), width=int(b.get("width") or 0), height=int(b.get("height") or 0), place=b.get("place"), sort=n)
        if row is None:
            key = save_bytes(png, subdir="avatar/backgrounds", filename_hint="bg.png") if png else None
            db.add(AvatarBackground(id=bid, image_key=key, image_hash=digest, **fields))
            bg_added += 1
            continue
        changed = digest != row.image_hash or any(getattr(row, k) != v for k, v in fields.items() if k != "sort")
        if png is not None and digest != row.image_hash:
            old = row.image_key
            row.image_key = save_bytes(png, subdir="avatar/backgrounds", filename_hint="bg.png")
            row.image_hash = digest
            delete_by_key(old)
        for k, v in fields.items():
            setattr(row, k, v)
        if changed:
            row.version += 1
            bg_updated += 1

    meta = _meta(db)
    meta.canvas = data.get("canvas") or meta.canvas
    meta.frame = data.get("frame") or meta.frame
    new_slots = [{"id": str(s["id"]), "name": str(s.get("name") or s["id"])} for s in (data.get("slots") or []) if isinstance(s, dict) and s.get("id")]
    changed_meta = new_slots != meta.slots or meta.frame != data.get("frame", meta.frame)
    meta.slots = new_slots or meta.slots
    if added or updated or bg_added or bg_updated or changed_meta:
        meta.version += 1
    missing = db.query(AvatarItem).filter(~AvatarItem.id.in_(seen) if seen else True).count()
    db.commit()
    return ImportReport(version=meta.version, added=added, updated=updated, unchanged=unchanged, backgrounds_added=bg_added, backgrounds_updated=bg_updated, missing_in_file=missing)


class AdminItem(BaseModel):
    id: str
    slot: str
    gender: str
    name: str
    set_id: str
    set_name: str
    url: str | None
    place: dict
    own_place: bool
    active: bool
    version: int


class AdminBackground(BaseModel):
    id: str
    name: str
    kind: str
    c1: str | None
    c2: str | None
    url: str | None
    active: bool
    version: int


class AdminCatalog(BaseModel):
    version: int
    slots: list
    items: list[AdminItem]
    backgrounds: list[AdminBackground]


def _admin_item(i: AvatarItem) -> AdminItem:
    return AdminItem(id=i.id, slot=i.slot, gender=i.gender, name=i.name, set_id=i.set_id, set_name=i.set_name, url=url_for_key(i.image_key), place=i.place, own_place=i.own_place, active=i.active, version=i.version)


@admin_router.get("/catalog", response_model=AdminCatalog)
def admin_catalog(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    meta = _meta(db)
    items = db.query(AvatarItem).order_by(AvatarItem.sort, AvatarItem.id).all()
    bgs = db.query(AvatarBackground).order_by(AvatarBackground.sort, AvatarBackground.id).all()
    db.commit()
    return AdminCatalog(
        version=meta.version,
        slots=meta.slots,
        items=[_admin_item(i) for i in items],
        backgrounds=[AdminBackground(id=b.id, name=b.name, kind=b.kind, c1=b.c1, c2=b.c2, url=url_for_key(b.image_key), active=b.active, version=b.version) for b in bgs],
    )


class ActiveIn(BaseModel):
    active: bool


def _bump(db: Session) -> None:
    _meta(db).version += 1


@admin_router.patch("/items/{item_id}", response_model=AdminItem)
def set_item_active(item_id: str, payload: ActiveIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    row = db.get(AvatarItem, item_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Нет такой детали")
    if row.active != payload.active:
        row.active = payload.active
        _bump(db)
    db.commit()
    return _admin_item(row)


@admin_router.patch("/backgrounds/{bg_id}", status_code=status.HTTP_204_NO_CONTENT)
def set_background_active(bg_id: str, payload: ActiveIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    row = db.get(AvatarBackground, bg_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Нет такого фона")
    if row.active != payload.active:
        row.active = payload.active
        _bump(db)
    db.commit()


@admin_router.delete("/items/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_item(item_id: str, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    row = db.get(AvatarItem, item_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Нет такой детали")
    key = row.image_key
    db.delete(row)
    _bump(db)
    db.commit()
    delete_by_key(key)


# ---------------------------------------------------------------------------- app


class CatalogItem(BaseModel):
    id: str
    slot: str
    gender: str
    set_id: str
    name: str
    url: str
    w: int
    h: int
    place: dict
    v: int


class CatalogBg(BaseModel):
    id: str
    name: str
    kind: str
    c1: str | None = None
    c2: str | None = None
    url: str | None = None
    w: int = 0
    h: int = 0
    place: dict | None = None
    v: int


class CatalogOut(BaseModel):
    version: int
    unchanged: bool = False
    canvas: dict | None = None
    frame: dict | None = None
    slots: list | None = None
    sets: list | None = None
    items: list[CatalogItem] | None = None
    backgrounds: list[CatalogBg] | None = None


@router.get("/avatar/catalog", response_model=CatalogOut)
def catalog(since: int | None = None, db: Session = Depends(get_db), _user: User = Depends(get_current_user)):
    """Everything the editor needs. `since` is the catalog version the phone already has: if it is still
    current, the answer is just {"unchanged": true} and nothing is downloaded again."""
    meta = _meta(db)
    db.commit()
    if since is not None and since == meta.version:
        return CatalogOut(version=meta.version, unchanged=True)
    items = db.query(AvatarItem).filter(AvatarItem.active.is_(True)).order_by(AvatarItem.sort, AvatarItem.id).all()
    bgs = db.query(AvatarBackground).filter(AvatarBackground.active.is_(True)).order_by(AvatarBackground.sort, AvatarBackground.id).all()
    sets: dict[str, str] = {}
    for i in items:
        if i.set_id:
            sets.setdefault(i.set_id, i.set_name)
    return CatalogOut(
        version=meta.version,
        canvas=meta.canvas,
        frame=meta.frame,
        slots=meta.slots,
        sets=[{"id": k, "name": v} for k, v in sets.items()],
        items=[CatalogItem(id=i.id, slot=i.slot, gender=i.gender, set_id=i.set_id, name=i.name, url=url_for_key(i.image_key) or "", w=i.width, h=i.height, place=i.place, v=i.version) for i in items],
        backgrounds=[CatalogBg(id=b.id, name=b.name, kind=b.kind, c1=b.c1, c2=b.c2, url=url_for_key(b.image_key), w=b.width, h=b.height, place=b.place, v=b.version) for b in bgs],
    )


@router.put("/users/me/avatar-look")
def save_my_avatar(
    look: str = Form(...),
    image: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Saves the finished avatar: the PNG the app drew from the parts and the choice behind it (which parts,
    by ID). The choice is checked against the catalog so a made-up ID or a part of the wrong gender is refused."""
    try:
        choice = json.loads(look)
    except ValueError:
        raise HTTPException(status_code=422, detail="Неверный выбор аватара")
    gender = choice.get("gender") if isinstance(choice, dict) else None
    slots = choice.get("slots") if isinstance(choice, dict) else None
    if gender not in GENDERS or not isinstance(slots, dict):
        raise HTTPException(status_code=422, detail="Неверный выбор аватара")
    clean: dict[str, str] = {}
    for slot, item_id in slots.items():
        row = db.get(AvatarItem, str(item_id))
        if row is None or not row.active or row.slot != slot or gender not in row.place:
            raise HTTPException(status_code=422, detail="Эта деталь недоступна")
        clean[slot] = row.id
    bg_id = choice.get("bg") or None
    if bg_id is not None:
        bg = db.get(AvatarBackground, str(bg_id))
        if bg is None or not bg.active:
            raise HTTPException(status_code=422, detail="Этот фон недоступен")
    data = image.file.read(MAX_AVATAR_BYTES + 1)
    if len(data) > MAX_AVATAR_BYTES:
        raise HTTPException(status_code=422, detail="Файл слишком большой")
    if not data.startswith(PNG_MAGIC):
        raise HTTPException(status_code=422, detail="Нужна картинка PNG")
    new_key = save_bytes(data, subdir=f"users/{user.id}/avatar", filename_hint="avatar.png")
    old_key = user.avatar_key
    user.avatar_key = new_key
    user.avatar_look = {"gender": gender, "slots": clean, "bg": bg_id, "catalog_version": _meta(db).version}
    db.commit()
    delete_by_key(old_key)  # the old picture goes at once; the phone drops its copy when it sees the new address
    return {"avatar_url": url_for_key(new_key), "avatar_look": user.avatar_look}
