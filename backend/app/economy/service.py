"""Transactional operations for diamonds, gift openings, and shop items."""

import random
import uuid
from datetime import date

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dates import dushanbe_today
from app.models.achievement import UserActivityDay, UserStreakFreeze
from app.models.economy import DiamondTransaction, GiftDefinition, GiftOpen, ShopProduct
from app.models.user import User


class EconomyError(Exception):
    """A user-facing wallet/shop error."""


def grant_diamonds(db: Session, user: User, amount: int, source: str, reference: str) -> int:
    """Credit a wallet once per source reference. Caller owns commit."""
    if amount <= 0:
        return 0
    try:
        with db.begin_nested():
            db.add(DiamondTransaction(user_id=user.id, amount=amount, source=source, reference=reference))
            db.flush()
    except IntegrityError:
        return 0
    locked = db.query(User).filter(User.id == user.id).with_for_update().one()
    locked.diamonds_balance += amount
    db.flush()
    return amount


def buy_product(db: Session, user: User, product: ShopProduct) -> None:
    """Charge diamonds and grant the configured item in one transaction."""
    locked = db.query(User).filter(User.id == user.id).with_for_update().one()
    if not product.enabled:
        raise EconomyError("Этот товар сейчас недоступен")
    if product.price_diamonds < 0 or product.quantity <= 0:
        raise EconomyError("У товара некорректная цена или количество")
    if locked.diamonds_balance < product.price_diamonds:
        raise EconomyError("Недостаточно бриллиантов")
    if product.item_type not in ("streak_freeze", "streak_merge"):
        raise EconomyError("Неизвестный тип товара")

    reference = f"shop:{product.sku}:{uuid.uuid4().hex}"
    locked.diamonds_balance -= product.price_diamonds
    db.add(DiamondTransaction(user_id=locked.id, amount=-product.price_diamonds, source="shop", reference=reference))
    if product.item_type == "streak_freeze":
        locked.streak_freezes = (locked.streak_freezes or 0) + product.quantity
    else:
        locked.streak_merge_items = (locked.streak_merge_items or 0) + product.quantity
    db.flush()


def use_streak_merge(db: Session, user: User) -> dict:
    """Consume one item and bank the unique active/freeze-covered days not
    already folded into this live streak. A later broken streak clears the
    bank; the calendar records themselves are never changed."""
    from app.achievements.streak import active_today
    from app.achievements.conditions import streak_with_freezes

    locked = db.query(User).filter(User.id == user.id).with_for_update().one()
    if (locked.streak_merge_items or 0) <= 0:
        raise EconomyError("У вас нет объединителя серии")
    if not active_today(db, locked):
        raise EconomyError("Сначала займитесь сегодня, затем примените объединитель")

    active_days = {row[0] for row in db.query(UserActivityDay.activity_date).filter(UserActivityDay.user_id == locked.id).all()}
    freeze_days = {row[0] for row in db.query(UserStreakFreeze.covered_date).filter(UserStreakFreeze.user_id == locked.id).all()}
    accumulated = active_days | freeze_days
    if not accumulated:
        raise EconomyError("Пока нет дней серии для объединения")

    raw_streak, _ = streak_with_freezes(db, locked, include_merged=False)
    # The item folds the full recorded history into the current active run.
    # Reusing it after a later break can restore the older recorded days too;
    # the permanent calendar itself is never edited.
    locked.streak_merge_days = max(0, len(accumulated) - raw_streak)
    locked.streak_merge_cursor = dushanbe_today()
    locked.streak_merge_items -= 1
    raw_streak, _ = streak_with_freezes(db, locked, include_merged=False)
    current_streak = raw_streak + locked.streak_merge_days
    db.flush()
    return {"current_streak_days": current_streak, "merged_days": locked.streak_merge_days, "items_left": locked.streak_merge_items}


def shop_state(db: Session, user: User) -> dict:
    products = db.query(ShopProduct).filter(ShopProduct.enabled.is_(True)).order_by(ShopProduct.sort_order, ShopProduct.id).all()
    return {
        "diamonds": user.diamonds_balance,
        "streak_freezes": user.streak_freezes or 0,
        "streak_merge_items": user.streak_merge_items or 0,
        "products": [product_out(p) for p in products],
    }


def product_out(product: ShopProduct) -> dict:
    return {
        "id": product.id, "sku": product.sku, "name": product.name,
        "description": product.description, "item_type": product.item_type,
        "quantity": product.quantity, "price_diamonds": product.price_diamonds,
        "icon_key": product.icon_key,
    }
