"""Promo codes and promo links: the user's "activate" endpoint, and the
admin side that manages both kinds. Same two-routers-one-file layout as
premium.py and notifications.py.
"""

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.dates import DUSHANBE_TZ, as_utc
from app.core.deps import get_current_admin, get_current_user
from app.database import get_db
from app.models.admin import Admin
from app.models.promo import PromoActivation, PromoCode, PromoLink
from app.models.user import User
from app.premium import get_premium_settings
from app.promo import PromoError, is_valid_code, normalize_code, normalize_link, redeem_promo
from app.schemas.promo import (
    PromoActivationOut,
    PromoCodeCreateIn,
    PromoCodeOut,
    PromoCodeUpdateIn,
    PromoLinkCreateIn,
    PromoLinkOut,
    PromoLinkUpdateIn,
    PromoSettingsIn,
    PromoSettingsOut,
    RedeemIn,
    RedeemOut,
)

router = APIRouter(tags=["promo"])
admin_router = APIRouter(prefix="/admin/promo", tags=["admin-promo"])


# --- The user's side -----------------------------------------------------------


@router.post("/promo/redeem", response_model=RedeemOut)
def redeem(payload: RedeemIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Activates a promo code or a pasted video link. 404 when there's no
    such code/link, 409 when it can't be used (already used by this user,
    expired, cap reached) -- `detail` says which, in words to show as is."""
    try:
        result = redeem_promo(db, user, payload.code)
    except PromoError as e:
        db.rollback()
        raise HTTPException(status_code=e.status_code, detail=str(e))
    db.commit()

    until = result.premium_until.astimezone(DUSHANBE_TZ).strftime("%d.%m.%Y")
    return RedeemOut(
        days=result.days,
        premium_until=result.premium_until,
        kind=result.kind,
        is_first_link=result.is_first_link,
        message=f"+{result.days} дн. GuYo Premium. Premium активен до {until}.",
    )


# --- Admin: helpers ------------------------------------------------------------


def _activation_counts(db: Session, column) -> dict[int, int]:
    return dict(
        db.query(column, func.count(PromoActivation.id)).filter(column.is_not(None)).group_by(column).all()
    )


def _code_out(code: PromoCode, activations: int) -> PromoCodeOut:
    return PromoCodeOut(
        id=code.id,
        code=code.code,
        days=code.days,
        enabled=code.enabled,
        expires_at=code.expires_at,
        max_activations=code.max_activations,
        note=code.note,
        activations=activations,
        created_at=code.created_at,
    )


def _link_out(link: PromoLink, activations: int) -> PromoLinkOut:
    return PromoLinkOut(
        id=link.id,
        url=link.url,
        title=link.title,
        repeat_days=link.repeat_days,
        enabled=link.enabled,
        activations=activations,
        created_at=link.created_at,
    )


def _checked_code(db: Session, raw: str, exclude_id: int | None = None) -> str:
    code = normalize_code(raw)
    if not is_valid_code(code):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Промокод: от 3 до 40 символов, только буквы, цифры, «-» и «_»",
        )
    taken = db.query(PromoCode).filter(PromoCode.code == code)
    if exclude_id is not None:
        taken = taken.filter(PromoCode.id != exclude_id)
    if taken.first() is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Такой промокод уже есть")
    return code


def _checked_link_key(db: Session, raw: str, exclude_id: int | None = None) -> str:
    key = normalize_link(raw)
    if key is None:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Это не похоже на ссылку")
    taken = db.query(PromoLink).filter(PromoLink.normalized_key == key)
    if exclude_id is not None:
        taken = taken.filter(PromoLink.id != exclude_id)
    existing = taken.first()
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Это видео уже добавлено: {existing.title or existing.url}",
        )
    return key


# --- Admin: codes --------------------------------------------------------------


@admin_router.get("/codes", response_model=list[PromoCodeOut])
def list_codes(db: Session = Depends(get_db), _admin: Admin = Depends(get_current_admin)):
    counts = _activation_counts(db, PromoActivation.promo_code_id)
    codes = db.query(PromoCode).order_by(PromoCode.created_at.desc(), PromoCode.id.desc()).all()
    return [_code_out(c, counts.get(c.id, 0)) for c in codes]


@admin_router.post("/codes", response_model=PromoCodeOut, status_code=status.HTTP_201_CREATED)
def create_code(payload: PromoCodeCreateIn, db: Session = Depends(get_db), _admin: Admin = Depends(get_current_admin)):
    code = PromoCode(
        code=_checked_code(db, payload.code),
        days=payload.days,
        enabled=payload.enabled,
        expires_at=as_utc(payload.expires_at) if payload.expires_at else None,
        max_activations=payload.max_activations,
        note=(payload.note or "").strip() or None,
    )
    db.add(code)
    db.commit()
    db.refresh(code)
    return _code_out(code, 0)


def _get_code_or_404(db: Session, code_id: int) -> PromoCode:
    code = db.get(PromoCode, code_id)
    if code is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Promo code not found")
    return code


@admin_router.patch("/codes/{code_id}", response_model=PromoCodeOut)
def update_code(
    code_id: int,
    payload: PromoCodeUpdateIn,
    db: Session = Depends(get_db),
    _admin: Admin = Depends(get_current_admin),
):
    """Changes only what is sent. Changing `days` affects future
    activations only -- past ones keep what they gave."""
    code = _get_code_or_404(db, code_id)
    fields = payload.model_dump(exclude_unset=True)
    if "code" in fields and fields["code"] is not None:
        code.code = _checked_code(db, fields["code"], exclude_id=code.id)
    if fields.get("days") is not None:
        code.days = fields["days"]
    if fields.get("enabled") is not None:
        code.enabled = fields["enabled"]
    if "expires_at" in fields:
        code.expires_at = as_utc(fields["expires_at"]) if fields["expires_at"] else None
    if "max_activations" in fields:
        code.max_activations = fields["max_activations"]
    if "note" in fields:
        code.note = (fields["note"] or "").strip() or None
    db.commit()
    db.refresh(code)
    return _code_out(code, _activation_counts(db, PromoActivation.promo_code_id).get(code.id, 0))


@admin_router.delete("/codes/{code_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_code(code_id: int, db: Session = Depends(get_db), _admin: Admin = Depends(get_current_admin)):
    """Only a code nobody has activated can be deleted -- an activated one
    is part of someone's Premium history. Disable it instead."""
    code = _get_code_or_404(db, code_id)
    if db.query(PromoActivation.id).filter(PromoActivation.promo_code_id == code.id).first() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Промокод уже активировали -- выключите его вместо удаления",
        )
    db.delete(code)
    db.commit()


# --- Admin: links --------------------------------------------------------------


@admin_router.get("/links", response_model=list[PromoLinkOut])
def list_links(db: Session = Depends(get_db), _admin: Admin = Depends(get_current_admin)):
    counts = _activation_counts(db, PromoActivation.promo_link_id)
    links = db.query(PromoLink).order_by(PromoLink.created_at.desc(), PromoLink.id.desc()).all()
    return [_link_out(link, counts.get(link.id, 0)) for link in links]


@admin_router.post("/links", response_model=PromoLinkOut, status_code=status.HTTP_201_CREATED)
def create_link(payload: PromoLinkCreateIn, db: Session = Depends(get_db), _admin: Admin = Depends(get_current_admin)):
    link = PromoLink(
        url=payload.url.strip(),
        normalized_key=_checked_link_key(db, payload.url),
        title=(payload.title or "").strip() or None,
        repeat_days=payload.repeat_days,
        enabled=payload.enabled,
    )
    db.add(link)
    db.commit()
    db.refresh(link)
    return _link_out(link, 0)


def _get_link_or_404(db: Session, link_id: int) -> PromoLink:
    link = db.get(PromoLink, link_id)
    if link is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Promo link not found")
    return link


@admin_router.patch("/links/{link_id}", response_model=PromoLinkOut)
def update_link(
    link_id: int,
    payload: PromoLinkUpdateIn,
    db: Session = Depends(get_db),
    _admin: Admin = Depends(get_current_admin),
):
    link = _get_link_or_404(db, link_id)
    fields = payload.model_dump(exclude_unset=True)
    if fields.get("url") is not None:
        link.normalized_key = _checked_link_key(db, fields["url"], exclude_id=link.id)
        link.url = fields["url"].strip()
    if "title" in fields:
        link.title = (fields["title"] or "").strip() or None
    if "repeat_days" in fields:
        link.repeat_days = fields["repeat_days"]
    if fields.get("enabled") is not None:
        link.enabled = fields["enabled"]
    db.commit()
    db.refresh(link)
    return _link_out(link, _activation_counts(db, PromoActivation.promo_link_id).get(link.id, 0))


@admin_router.delete("/links/{link_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_link(link_id: int, db: Session = Depends(get_db), _admin: Admin = Depends(get_current_admin)):
    """Same rule as codes: an activated link is history -- disable it."""
    link = _get_link_or_404(db, link_id)
    if db.query(PromoActivation.id).filter(PromoActivation.promo_link_id == link.id).first() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Ссылку уже активировали -- выключите её вместо удаления",
        )
    db.delete(link)
    db.commit()


# --- Admin: link rewards and history -------------------------------------------


@admin_router.get("/settings", response_model=PromoSettingsOut)
def get_settings(db: Session = Depends(get_db), _admin: Admin = Depends(get_current_admin)):
    s = get_premium_settings(db)
    db.commit()
    return PromoSettingsOut(promo_link_first_days=s.promo_link_first_days, promo_link_repeat_days=s.promo_link_repeat_days)


@admin_router.put("/settings", response_model=PromoSettingsOut)
def update_settings(payload: PromoSettingsIn, db: Session = Depends(get_db), _admin: Admin = Depends(get_current_admin)):
    s = get_premium_settings(db)
    s.promo_link_first_days = payload.promo_link_first_days
    s.promo_link_repeat_days = payload.promo_link_repeat_days
    db.commit()
    return PromoSettingsOut(promo_link_first_days=s.promo_link_first_days, promo_link_repeat_days=s.promo_link_repeat_days)


@admin_router.get("/activations", response_model=list[PromoActivationOut])
def list_activations(
    code_id: int | None = Query(default=None),
    link_id: int | None = Query(default=None),
    db: Session = Depends(get_db),
    _admin: Admin = Depends(get_current_admin),
):
    """Who activated what, newest first -- everything, or one code's or
    one link's."""
    query = (
        db.query(PromoActivation, User.login, User.public_id, PromoCode.code, PromoLink.title, PromoLink.url)
        .join(User, User.id == PromoActivation.user_id)
        .outerjoin(PromoCode, PromoCode.id == PromoActivation.promo_code_id)
        .outerjoin(PromoLink, PromoLink.id == PromoActivation.promo_link_id)
    )
    if code_id is not None:
        query = query.filter(PromoActivation.promo_code_id == code_id)
    if link_id is not None:
        query = query.filter(PromoActivation.promo_link_id == link_id)
    rows = query.order_by(PromoActivation.created_at.desc(), PromoActivation.id.desc()).limit(500).all()
    return [
        PromoActivationOut(
            id=a.id,
            user_id=a.user_id,
            user_login=login,
            user_public_id=public_id,
            promo_code_id=a.promo_code_id,
            promo_link_id=a.promo_link_id,
            label=code or title or url or "",
            days=a.days,
            is_first_link=a.is_first_link,
            created_at=a.created_at,
        )
        for a, login, public_id, code, title, url in rows
    ]
