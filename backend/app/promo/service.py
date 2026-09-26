"""Activating a promo code or promo link -- the one place either becomes
Premium days.

A user types or pastes ONE thing; redeem_promo decides whether it is a
link or a code (app/promo/links.py's looks_like_link), checks it, records
a PromoActivation and hands the days to grant_premium -- so a promo
extends an active subscription exactly like a payment does, and shows up
in the same Premium history.
"""

import re
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dates import utc_now
from app.models.premium import GRANT_SOURCE_PROMO
from app.models.promo import PromoActivation, PromoCode, PromoLink
from app.models.user import User
from app.premium import get_premium_settings, grant_premium
from app.promo.links import looks_like_link, normalize_link

# Letters (any alphabet), digits, "-" and "_"; 3 to 40 of them. No "/" or
# "." -- that is what lets looks_like_link tell a code from a link.
_CODE_PATTERN = re.compile(r"^[\w-]{3,40}$")


class PromoError(Exception):
    """A promo that can't be activated. The message is shown to the user
    as is; `status_code` is what the endpoint answers with."""

    def __init__(self, message: str, status_code: int):
        super().__init__(message)
        self.status_code = status_code


NOT_FOUND = 404
CONFLICT = 409


def normalize_code(raw: str) -> str:
    """Trimmed and upper-cased -- "guyo2026" and " GUYO2026 " are the same
    code. Used both when the admin saves a code and when a user enters
    one, so the two can never disagree."""
    return raw.strip().upper()


def is_valid_code(code: str) -> bool:
    return bool(_CODE_PATTERN.match(code))


@dataclass
class RedeemResult:
    days: int
    premium_until: datetime
    kind: str  # "code" or "link"
    is_first_link: bool = False


def code_activation_count(db: Session, code_id: int) -> int:
    return (
        db.query(func.count(PromoActivation.id)).filter(PromoActivation.promo_code_id == code_id).scalar() or 0
    )


def redeem_promo(db: Session, user: User, raw: str) -> RedeemResult:
    """Activates whatever the user entered, or raises PromoError. Does NOT
    commit -- the caller owns the transaction."""
    if looks_like_link(raw):
        return _redeem_link(db, user, raw)
    return _redeem_code(db, user, raw)


def _redeem_code(db: Session, user: User, raw: str) -> RedeemResult:
    code_text = normalize_code(raw)
    # Locked so two users racing for the last activation of a capped code
    # can't both get it.
    code = db.query(PromoCode).filter(PromoCode.code == code_text).with_for_update().first()
    if code is None or not code.enabled:
        raise PromoError("Такого промокода нет. Проверьте, правильно ли он введён.", NOT_FOUND)
    if code.expires_at is not None and code.expires_at <= utc_now():
        raise PromoError("Срок действия этого промокода закончился.", CONFLICT)

    already = (
        db.query(PromoActivation.id)
        .filter(PromoActivation.user_id == user.id, PromoActivation.promo_code_id == code.id)
        .first()
    )
    if already is not None:
        raise PromoError("Вы уже активировали этот промокод.", CONFLICT)
    if code.max_activations is not None and code_activation_count(db, code.id) >= code.max_activations:
        raise PromoError("Этот промокод уже использовали максимальное число раз.", CONFLICT)

    activation = PromoActivation(user_id=user.id, promo_code_id=code.id, days=code.days)
    _insert_activation(db, activation, "Вы уже активировали этот промокод.")
    grant = grant_premium(
        db,
        user,
        code.days,
        note=f"Промокод {code.code}",
        source=GRANT_SOURCE_PROMO,
        reason=f"Промокод {code.code} активирован: +{code.days} дн.",
    )
    activation.grant_id = grant.id
    return RedeemResult(days=code.days, premium_until=grant.ends_at, kind="code")


def _redeem_link(db: Session, user: User, raw: str) -> RedeemResult:
    key = normalize_link(raw)
    link = None
    if key is not None:
        link = db.query(PromoLink).filter(PromoLink.normalized_key == key).first()
    if link is None or not link.enabled:
        raise PromoError("Эта ссылка не участвует в акции. Проверьте, что скопировали ссылку на видео GuYo.", NOT_FOUND)

    # Locks this user's row, so two links pasted at the same moment can't
    # both be counted as the user's first.
    db.query(User.id).filter(User.id == user.id).with_for_update().one()

    already = (
        db.query(PromoActivation.id)
        .filter(PromoActivation.user_id == user.id, PromoActivation.promo_link_id == link.id)
        .first()
    )
    if already is not None:
        raise PromoError("Вы уже активировали эту ссылку. Ищите новые видео GuYo!", CONFLICT)

    had_link_before = (
        db.query(PromoActivation.id)
        .filter(PromoActivation.user_id == user.id, PromoActivation.promo_link_id.is_not(None))
        .first()
        is not None
    )
    settings = get_premium_settings(db)
    if had_link_before:
        days = link.repeat_days or settings.promo_link_repeat_days
    else:
        days = settings.promo_link_first_days

    activation = PromoActivation(user_id=user.id, promo_link_id=link.id, days=days, is_first_link=not had_link_before)
    _insert_activation(db, activation, "Вы уже активировали эту ссылку. Ищите новые видео GuYo!")
    grant = grant_premium(
        db,
        user,
        days,
        note=f"Ссылка: {link.title or link.url}",
        source=GRANT_SOURCE_PROMO,
        reason=f"Ссылка активирована: +{days} дн.",
    )
    activation.grant_id = grant.id
    return RedeemResult(days=days, premium_until=grant.ends_at, kind="link", is_first_link=not had_link_before)


def _insert_activation(db: Session, activation: PromoActivation, duplicate_message: str) -> None:
    """The unique constraints are what really decide "once per user"; the
    checks above only give the common case a friendly message. Runs in a
    SAVEPOINT so losing a race rolls back just this insert."""
    try:
        with db.begin_nested():
            db.add(activation)
            db.flush()
    except IntegrityError:
        raise PromoError(duplicate_message, CONFLICT)
