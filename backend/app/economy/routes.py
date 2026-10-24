"""User-facing gift/shop routes and the gift catalog admin API."""

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin, get_current_user
from app.database import get_db
from app.economy import service
from app.economy.service import EconomyError
from app.models.economy import GiftDefinition, ShopProduct
from app.models.user import User

shop_router = APIRouter(prefix="/shop", tags=["shop"])
admin_router = APIRouter(prefix="/admin/economy", tags=["admin-economy"])


class ProductIn(BaseModel):
    sku: str = Field(min_length=1, max_length=64, pattern=r"^[a-z0-9][a-z0-9-]*$")
    name: str = Field(min_length=1, max_length=120)
    description: str = Field(default="", max_length=2000)
    item_type: str
    quantity: int = Field(ge=1, le=10000)
    price_diamonds: int = Field(ge=0, le=1_000_000)
    icon_key: str = Field(default="gift", min_length=1, max_length=32)
    enabled: bool = True
    sort_order: int = Field(default=0, ge=0, le=10000)


class GiftIn(BaseModel):
    key: str = Field(min_length=1, max_length=64, pattern=r"^[a-z0-9][a-z0-9-]*$")
    name: str = Field(min_length=1, max_length=120)
    description: str = Field(default="", max_length=2000)
    icon_key: str = Field(default="gift", min_length=1, max_length=32)
    reward_min: int = Field(ge=0, le=1_000_000)
    reward_max: int = Field(ge=0, le=1_000_000)
    cooldown_days: int = Field(default=1, ge=1, le=3650)
    requires_activity: bool = True
    enabled: bool = True
    sort_order: int = Field(default=0, ge=0, le=10000)


def _refuse(error: EconomyError) -> HTTPException:
    return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(error))


def _product_admin_out(product: ShopProduct) -> dict:
    return {**service.product_out(product), "enabled": product.enabled, "sort_order": product.sort_order}


def _gift_admin_out(gift: GiftDefinition) -> dict:
    return {
        "id": gift.id, "key": gift.key, "name": gift.name, "description": gift.description,
        "icon_key": gift.icon_key, "reward_min": gift.reward_min, "reward_max": gift.reward_max,
        "cooldown_days": gift.cooldown_days, "requires_activity": gift.requires_activity,
        "enabled": gift.enabled, "sort_order": gift.sort_order,
    }


@shop_router.get("")
def get_shop(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return service.shop_state(db, user)


@shop_router.post("/{product_id}/buy")
def buy_product(product_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    product = db.get(ShopProduct, product_id)
    if product is None or not product.enabled:
        raise HTTPException(status_code=404, detail="Товар не найден")
    try:
        service.buy_product(db, user, product)
    except EconomyError as e:
        db.rollback()
        raise _refuse(e) from None
    db.commit()
    db.refresh(user)
    return service.shop_state(db, user)


@shop_router.post("/use/streak-merge")
def use_streak_merge(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    try:
        result = service.use_streak_merge(db, user)
    except EconomyError as e:
        db.rollback()
        raise _refuse(e) from None
    db.commit()
    return result


@admin_router.get("/products")
def list_products(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    return [_product_admin_out(p) for p in db.query(ShopProduct).order_by(ShopProduct.sort_order, ShopProduct.id).all()]


@admin_router.post("/products", status_code=status.HTTP_201_CREATED)
def create_product(payload: ProductIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    if payload.item_type not in ("streak_freeze", "streak_merge"):
        raise HTTPException(status_code=422, detail="Неизвестный тип товара")
    product = ShopProduct(**payload.model_dump())
    db.add(product)
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=409, detail="Такой артикул уже существует") from None
    db.refresh(product)
    return _product_admin_out(product)


@admin_router.put("/products/{product_id}")
def update_product(product_id: int, payload: ProductIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    product = db.get(ShopProduct, product_id)
    if product is None:
        raise HTTPException(status_code=404, detail="Товар не найден")
    if payload.item_type not in ("streak_freeze", "streak_merge"):
        raise HTTPException(status_code=422, detail="Неизвестный тип товара")
    for key, value in payload.model_dump().items():
        setattr(product, key, value)
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=409, detail="Такой артикул уже существует") from None
    db.refresh(product)
    return _product_admin_out(product)


@admin_router.delete("/products/{product_id}", status_code=status.HTTP_204_NO_CONTENT)
def disable_product(product_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    product = db.get(ShopProduct, product_id)
    if product is None:
        raise HTTPException(status_code=404, detail="Товар не найден")
    product.enabled = False
    db.commit()


@admin_router.get("/gifts")
def list_gift_definitions(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    return [_gift_admin_out(g) for g in db.query(GiftDefinition).order_by(GiftDefinition.sort_order, GiftDefinition.id).all()]


@admin_router.post("/gifts", status_code=status.HTTP_201_CREATED)
def create_gift(payload: GiftIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    if payload.reward_max < payload.reward_min:
        raise HTTPException(status_code=422, detail="Максимальная награда меньше минимальной")
    gift = GiftDefinition(**payload.model_dump())
    db.add(gift)
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=409, detail="Такой ключ подарка уже существует") from None
    db.refresh(gift)
    return _gift_admin_out(gift)


@admin_router.put("/gifts/{gift_id}")
def update_gift(gift_id: int, payload: GiftIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    gift = db.get(GiftDefinition, gift_id)
    if gift is None:
        raise HTTPException(status_code=404, detail="Подарок не найден")
    if payload.reward_max < payload.reward_min:
        raise HTTPException(status_code=422, detail="Максимальная награда меньше минимальной")
    for key, value in payload.model_dump().items():
        setattr(gift, key, value)
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=409, detail="Такой ключ подарка уже существует") from None
    db.refresh(gift)
    return _gift_admin_out(gift)


@admin_router.delete("/gifts/{gift_id}", status_code=status.HTTP_204_NO_CONTENT)
def disable_gift(gift_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    gift = db.get(GiftDefinition, gift_id)
    if gift is None:
        raise HTTPException(status_code=404, detail="Подарок не найден")
    gift.enabled = False
    db.commit()


class AdminGiftIn(BaseModel):
    # A login (any case) or the 9-digit public ID.
    user: str = Field(min_length=1, max_length=64)
    amount: int = Field(ge=1, le=100_000)
    note: str = Field(default="", max_length=300)


_GIFT_TEXTS = {
    "ru": ("Вам подарок!", "Вам подарили {n} бриллиантов"),
    "tg": ("Ба шумо тӯҳфа!", "Ба шумо {n} бриллиант тӯҳфа карданд"),
    "uz": ("Sizga sovg'a!", "Sizga {n} ta brilliant sovg'a qilindi"),
    "en": ("A gift for you!", "You were given {n} diamonds"),
}


@admin_router.post("/gift")
def gift_diamonds(payload: AdminGiftIn, db: Session = Depends(get_db), admin=Depends(get_current_admin)):
    """Gives diamonds to one person by hand (an event, a prize, a correction)
    and tells them with a notification."""
    import uuid

    from sqlalchemy import func

    from app.notifications.service import send_notification

    key = payload.user.strip()
    query = db.query(User).filter(User.deleted_at.is_(None))
    user = query.filter(User.public_id == int(key)).first() if key.isdigit() else None
    if user is None:
        user = query.filter(func.lower(User.login) == key.lower()).first()
    if user is None:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    service.grant_diamonds(db, user, payload.amount, "admin_gift", f"admin:{admin.id}:{uuid.uuid4().hex}")
    lang = user.ui_language if user.ui_language in _GIFT_TEXTS else "ru"
    title, body = _GIFT_TEXTS[lang]
    body = body.format(n=payload.amount)
    if payload.note.strip():
        body = f"{body}. {payload.note.strip()}"
    send_notification(db, user, body, title=title, source="admin_gift")
    db.commit()
    db.refresh(user)
    return {"user_id": user.id, "login": user.login, "amount": payload.amount, "diamonds": user.diamonds_balance}
