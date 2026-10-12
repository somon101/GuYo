"""API keys (Admin Web) and the external API v1 for achievements.

Admin: /admin/api-keys -- create (the full key is returned ONCE), list,
enable/disable, delete. External: /api/v1/... with header `X-API-Key: <key>`
(or `Authorization: Bearer <key>`): full CRUD of achievement definitions,
their icons and order. Same validation and storage as Admin Web's own
achievement endpoints (app/routers/admin_achievements.py).
"""

import hashlib
import secrets
from datetime import datetime

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.achievements import CONDITION_TYPE_LABELS
from app.core.dates import utc_now
from app.core.deps import get_current_admin
from app.core.storage import delete_by_key, save_icon_upload
from app.database import get_db
from app.models.achievement import VISIBILITY_VISIBLE, Achievement
from app.models.api_key import ApiKey
from app.routers.admin_achievements import (
    _achievement_out,
    _earned_counts,
    _get_achievement_or_404,
    _read_validated_icon,
    _validate_condition_type,
    _validate_visibility,
)

SCOPE_ACHIEVEMENTS = "achievements"


def _hash(key: str) -> str:
    return hashlib.sha256(key.encode()).hexdigest()


# --- Admin Web: manage keys ---------------------------------------------------------

admin_router = APIRouter(prefix="/admin/api-keys", tags=["admin-api-keys"])


class ApiKeyIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)


class ApiKeyPatch(BaseModel):
    enabled: bool


class ApiKeyOut(BaseModel):
    id: int
    name: str
    key_prefix: str
    scopes: list[str]
    enabled: bool
    created_at: datetime | None
    last_used_at: datetime | None


class ApiKeyCreatedOut(ApiKeyOut):
    key: str


def _key_out(k: ApiKey) -> ApiKeyOut:
    return ApiKeyOut(
        id=k.id, name=k.name, key_prefix=k.key_prefix, scopes=list(k.scopes or []), enabled=k.enabled,
        created_at=k.created_at, last_used_at=k.last_used_at,
    )


@admin_router.get("", response_model=list[ApiKeyOut])
def list_api_keys(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    return [_key_out(k) for k in db.query(ApiKey).order_by(ApiKey.id.desc()).all()]


@admin_router.post("", response_model=ApiKeyCreatedOut, status_code=status.HTTP_201_CREATED)
def create_api_key(payload: ApiKeyIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    key = "guyo_" + secrets.token_urlsafe(24)
    row = ApiKey(name=payload.name.strip(), key_prefix=key[:12], key_hash=_hash(key), scopes=[SCOPE_ACHIEVEMENTS], enabled=True)
    db.add(row)
    db.commit()
    db.refresh(row)
    return ApiKeyCreatedOut(**_key_out(row).model_dump(), key=key)


@admin_router.patch("/{key_id}", response_model=ApiKeyOut)
def update_api_key(key_id: int, payload: ApiKeyPatch, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    row = db.get(ApiKey, key_id)
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="API key not found")
    row.enabled = payload.enabled
    db.commit()
    db.refresh(row)
    return _key_out(row)


@admin_router.delete("/{key_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_api_key(key_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    row = db.get(ApiKey, key_id)
    if row is not None:
        db.delete(row)
        db.commit()


# --- External API v1 ----------------------------------------------------------------------


def require_api_key(request: Request, db: Session = Depends(get_db)) -> ApiKey:
    key = request.headers.get("x-api-key") or ""
    auth = request.headers.get("authorization") or ""
    if not key and auth.lower().startswith("bearer "):
        key = auth[7:].strip()
    row = db.query(ApiKey).filter(ApiKey.key_hash == _hash(key)).first() if key else None
    if row is None or not row.enabled:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or disabled API key")
    if SCOPE_ACHIEVEMENTS not in (row.scopes or []):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="This key has no access to achievements")
    row.last_used_at = utc_now()
    db.commit()
    return row


api_router = APIRouter(prefix="/api/v1", tags=["public-api-v1"])


class AchievementCreateIn(BaseModel):
    title: str = Field(min_length=1, max_length=255)
    description: str = Field(min_length=1, max_length=500)
    condition_type: str
    condition_value: int = Field(ge=1)
    color: str = Field(default="#6366F1", pattern=r"^#[0-9A-Fa-f]{6}$")
    visibility: str = VISIBILITY_VISIBLE
    show_before_unlock: bool = True
    enabled: bool = True
    order: int | None = None
    title_tg: str | None = Field(default=None, max_length=255)
    title_uz: str | None = Field(default=None, max_length=255)
    description_tg: str | None = Field(default=None, max_length=500)
    description_uz: str | None = Field(default=None, max_length=500)


class AchievementPatchIn(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = Field(default=None, min_length=1, max_length=500)
    condition_type: str | None = None
    condition_value: int | None = Field(default=None, ge=1)
    color: str | None = Field(default=None, pattern=r"^#[0-9A-Fa-f]{6}$")
    visibility: str | None = None
    show_before_unlock: bool | None = None
    enabled: bool | None = None
    order: int | None = None
    title_tg: str | None = Field(default=None, max_length=255)
    title_uz: str | None = Field(default=None, max_length=255)
    description_tg: str | None = Field(default=None, max_length=500)
    description_uz: str | None = Field(default=None, max_length=500)


class OrderIn(BaseModel):
    ids: list[int] = Field(min_length=1)


def _out(request: Request, a: Achievement, earned: int | None = None) -> dict:
    data = _achievement_out(a, earned).model_dump()
    if data.get("icon_url") and data["icon_url"].startswith("/"):
        base = str(request.base_url).rstrip("/")
        proto = request.headers.get("x-forwarded-proto")
        if proto and "://" in base:
            base = proto.split(",")[0].strip() + base[base.index("://"):]
        data["icon_url"] = base + data["icon_url"]
    return data


@api_router.get("/me")
def whoami(key: ApiKey = Depends(require_api_key)):
    """Check a key: its name and what it may access."""
    return {"name": key.name, "scopes": key.scopes, "key_prefix": key.key_prefix}


@api_router.get("/achievements/condition-types")
def condition_types(_key: ApiKey = Depends(require_api_key)):
    return [{"id": k, "label": v} for k, v in CONDITION_TYPE_LABELS.items()]


@api_router.get("/achievements")
def list_achievements(request: Request, db: Session = Depends(get_db), _key: ApiKey = Depends(require_api_key)):
    counts = _earned_counts(db)
    rows = db.query(Achievement).order_by(Achievement.order, Achievement.id).all()
    return [_out(request, a, counts.get(a.id, 0)) for a in rows]


@api_router.get("/achievements/{achievement_id}")
def get_achievement(achievement_id: int, request: Request, db: Session = Depends(get_db), _key: ApiKey = Depends(require_api_key)):
    return _out(request, _get_achievement_or_404(db, achievement_id))


@api_router.post("/achievements", status_code=status.HTTP_201_CREATED)
def create_achievement(payload: AchievementCreateIn, request: Request, db: Session = Depends(get_db), _key: ApiKey = Depends(require_api_key)):
    _validate_condition_type(payload.condition_type)
    _validate_visibility(payload.visibility)
    order = payload.order
    if order is None:
        last = db.query(Achievement.order).order_by(Achievement.order.desc()).first()
        order = (last[0] + 1) if last else 0
    a = Achievement(
        title=payload.title.strip(), description=payload.description.strip(), icon_key=None, color=payload.color,
        condition_type=payload.condition_type, condition_value=payload.condition_value, enabled=payload.enabled,
        visibility=payload.visibility, show_before_unlock=payload.show_before_unlock, order=order,
        title_tg=(payload.title_tg or "").strip() or None, title_uz=(payload.title_uz or "").strip() or None,
        description_tg=(payload.description_tg or "").strip() or None,
        description_uz=(payload.description_uz or "").strip() or None,
    )
    db.add(a)
    db.commit()
    db.refresh(a)
    return _out(request, a, 0)


@api_router.patch("/achievements/{achievement_id}")
def update_achievement(
    achievement_id: int, payload: AchievementPatchIn, request: Request, db: Session = Depends(get_db),
    _key: ApiKey = Depends(require_api_key),
):
    a = _get_achievement_or_404(db, achievement_id)
    fields = payload.model_dump(exclude_unset=True)
    if fields.get("condition_type") is not None:
        _validate_condition_type(fields["condition_type"])
    if fields.get("visibility") is not None:
        _validate_visibility(fields["visibility"])
    for name, value in fields.items():
        if name.endswith(("_tg", "_uz")):
            # "" or null clears a translation (falls back to Russian).
            setattr(a, name, (value or "").strip() or None)
            continue
        if value is None:
            continue
        setattr(a, name, value.strip() if isinstance(value, str) and name in ("title", "description") else value)
    db.commit()
    db.refresh(a)
    return _out(request, a)


@api_router.delete("/achievements/{achievement_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_achievement(achievement_id: int, db: Session = Depends(get_db), _key: ApiKey = Depends(require_api_key)):
    """Deletes it for everyone (users who earned it lose it). To retire it but
    let holders keep it, PATCH {"enabled": false} instead."""
    a = _get_achievement_or_404(db, achievement_id)
    icon_key = a.icon_key
    db.delete(a)
    db.commit()
    delete_by_key(icon_key)


@api_router.put("/achievements/order")
def reorder(payload: OrderIn, request: Request, db: Session = Depends(get_db), _key: ApiKey = Depends(require_api_key)):
    rows = db.query(Achievement).filter(Achievement.id.in_(payload.ids)).all()
    by_id = {a.id: a for a in rows}
    missing = [i for i in payload.ids if i not in by_id]
    if missing:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Unknown achievement ids: {missing}")
    for position, aid in enumerate(payload.ids):
        by_id[aid].order = position
    db.commit()
    counts = _earned_counts(db)
    return [_out(request, a, counts.get(a.id, 0)) for a in db.query(Achievement).order_by(Achievement.order, Achievement.id)]


@api_router.put("/achievements/{achievement_id}/icon")
def upload_icon(
    achievement_id: int, request: Request, icon: UploadFile = File(...), db: Session = Depends(get_db),
    _key: ApiKey = Depends(require_api_key),
):
    """PNG / JPEG / WEBP up to 5 MB (multipart field `icon`)."""
    a = _get_achievement_or_404(db, achievement_id)
    _read_validated_icon(icon)
    old = a.icon_key
    a.icon_key = save_icon_upload(icon, subdir="achievements/icons")
    db.commit()
    delete_by_key(old)
    db.refresh(a)
    return _out(request, a)


@api_router.delete("/achievements/{achievement_id}/icon")
def remove_icon(achievement_id: int, request: Request, db: Session = Depends(get_db), _key: ApiKey = Depends(require_api_key)):
    a = _get_achievement_or_404(db, achievement_id)
    old = a.icon_key
    a.icon_key = None
    db.commit()
    delete_by_key(old)
    db.refresh(a)
    return _out(request, a)
