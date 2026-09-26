"""GuYo Premium: the user's own status, and the admin side that grants it.

Both live here for the same reason notifications.py holds both of its
sides: two views of the same tables. Payment happens outside the app --
the admin grants a period by hand after a transfer arrives.
"""

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.core.dates import utc_now
from app.core.deps import get_current_admin, get_current_user
from app.database import get_db
from app.models.admin import Admin
from app.models.premium import PremiumGrant
from app.models.user import User
from app.premium import LessonQuota, get_premium_settings, grant_premium, lesson_quota, premium_until, revoke_premium
from app.schemas.premium import (
    GrantPremiumIn,
    LessonQuotaOut,
    PremiumGrantOut,
    PremiumSettingsIn,
    PremiumSettingsOut,
    PremiumStatusOut,
    PremiumUserOut,
)

router = APIRouter(tags=["premium"])
admin_router = APIRouter(prefix="/admin/premium", tags=["admin-premium"])


def quota_out(quota: LessonQuota) -> LessonQuotaOut:
    return LessonQuotaOut(
        daily_limit=quota.daily_limit,
        daily_used=quota.daily_used,
        weekly_limit=quota.weekly_limit,
        weekly_used=quota.weekly_used,
        remaining=quota.remaining,
        blocked_by=quota.blocked_by,
        resets_at=quota.resets_at,
    )


def _settings_out(db: Session) -> PremiumSettingsOut:
    s = get_premium_settings(db)
    return PremiumSettingsOut(
        premium_enabled=s.premium_enabled,
        free_daily_lesson_limit=s.free_daily_lesson_limit,
        free_weekly_lesson_limit=s.free_weekly_lesson_limit,
        premium_daily_lesson_limit=s.premium_daily_lesson_limit,
        premium_weekly_lesson_limit=s.premium_weekly_lesson_limit,
        adaptive_lessons_premium_only=s.adaptive_lessons_premium_only,
        personal_quests_premium_only=s.personal_quests_premium_only,
        price_text=s.price_text,
        payment_instructions=s.payment_instructions,
    )


# --- The user's own status ---------------------------------------------------


@router.get("/premium/me", response_model=PremiumStatusOut)
def get_my_premium(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Premium status, how to pay, and today's/this week's lesson counter
    -- what both the Premium screen and Главная's counter draw from."""
    settings = get_premium_settings(db)
    quota = lesson_quota(db, user)
    db.commit()  # get_premium_settings may have just created the settings row
    return PremiumStatusOut(
        is_premium=quota.is_premium,
        premium_until=quota.premium_until,
        premium_enabled=settings.premium_enabled,
        public_id=user.public_id,
        price_text=settings.price_text,
        payment_instructions=settings.payment_instructions,
        adaptive_lessons_premium_only=settings.adaptive_lessons_premium_only,
        personal_quests_premium_only=settings.personal_quests_premium_only,
        lessons=quota_out(quota),
    )


# --- Admin: settings -----------------------------------------------------------


@admin_router.get("/settings", response_model=PremiumSettingsOut)
def get_settings(db: Session = Depends(get_db), _admin: Admin = Depends(get_current_admin)):
    out = _settings_out(db)
    db.commit()
    return out


@admin_router.put("/settings", response_model=PremiumSettingsOut)
def update_settings(payload: PremiumSettingsIn, db: Session = Depends(get_db), _admin: Admin = Depends(get_current_admin)):
    """A null limit means unlimited. Changing a limit takes effect on the
    very next lesson anyone creates -- nothing already created is touched."""
    s = get_premium_settings(db)
    s.premium_enabled = payload.premium_enabled
    s.free_daily_lesson_limit = payload.free_daily_lesson_limit
    s.free_weekly_lesson_limit = payload.free_weekly_lesson_limit
    s.premium_daily_lesson_limit = payload.premium_daily_lesson_limit
    s.premium_weekly_lesson_limit = payload.premium_weekly_lesson_limit
    s.adaptive_lessons_premium_only = payload.adaptive_lessons_premium_only
    s.personal_quests_premium_only = payload.personal_quests_premium_only
    s.price_text = payload.price_text.strip()
    s.payment_instructions = payload.payment_instructions.strip()
    db.commit()
    return _settings_out(db)


# --- Admin: subscribers --------------------------------------------------------


def _get_user_or_404(db: Session, user_id: int) -> User:
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return user


def _grant_out(grant: PremiumGrant, admin_logins: dict[int, str]) -> PremiumGrantOut:
    return PremiumGrantOut(
        id=grant.id,
        user_id=grant.user_id,
        starts_at=grant.starts_at,
        ends_at=grant.ends_at,
        days=grant.days,
        source=grant.source,
        note=grant.note,
        granted_by_admin_login=admin_logins.get(grant.granted_by_admin_id) if grant.granted_by_admin_id else None,
        revoked_at=grant.revoked_at,
        created_at=grant.created_at,
    )


def _admin_logins(db: Session) -> dict[int, str]:
    return {a.id: a.login for a in db.query(Admin).all()}


@admin_router.get("/users", response_model=list[PremiumUserOut])
def list_premium_users(db: Session = Depends(get_db), _admin: Admin = Depends(get_current_admin)):
    """Every account that has ever had a grant, current subscribers first
    (soonest to expire at the top), then former ones. Asks premium_until
    per account -- the one definition of Premium -- since the list is only
    ever as long as the number of people who have paid."""
    now = utc_now()
    user_ids = [user_id for (user_id,) in db.query(PremiumGrant.user_id).distinct().all()]
    users = db.query(User).filter(User.id.in_(user_ids)).all() if user_ids else []

    rows = []
    for u in users:
        until = premium_until(db, u, now=now)
        rows.append(
            PremiumUserOut(
                user_id=u.id,
                public_id=u.public_id,
                login=u.login,
                first_name=u.first_name,
                last_name=u.last_name,
                is_premium=until is not None,
                premium_until=until,
            )
        )
    rows.sort(key=lambda r: (not r.is_premium, r.premium_until or now, r.login))
    return rows


@admin_router.get("/grants", response_model=list[PremiumGrantOut])
def list_grants(
    user_id: int | None = Query(default=None),
    db: Session = Depends(get_db),
    _admin: Admin = Depends(get_current_admin),
):
    """Every grant, newest first -- or one user's history."""
    query = db.query(PremiumGrant)
    if user_id is not None:
        query = query.filter(PremiumGrant.user_id == user_id)
    grants = query.order_by(PremiumGrant.created_at.desc(), PremiumGrant.id.desc()).limit(500).all()
    logins = _admin_logins(db)
    return [_grant_out(g, logins) for g in grants]


@admin_router.post("/users/{user_id}/grant", response_model=PremiumGrantOut, status_code=status.HTTP_201_CREATED)
def grant(
    user_id: int,
    payload: GrantPremiumIn,
    db: Session = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    """Grants `days` of Premium after a payment arrived. Extends an active
    subscription rather than overlapping it, and notifies the user."""
    user = _get_user_or_404(db, user_id)
    new_grant = grant_premium(db, user, payload.days, note=payload.note, admin=admin)
    db.commit()
    db.refresh(new_grant)
    return _grant_out(new_grant, _admin_logins(db))


@admin_router.post("/users/{user_id}/revoke", status_code=status.HTTP_204_NO_CONTENT)
def revoke(user_id: int, db: Session = Depends(get_db), _admin: Admin = Depends(get_current_admin)):
    """Ends the user's Premium now. The grants stay in the history, marked
    revoked."""
    user = _get_user_or_404(db, user_id)
    revoke_premium(db, user)
    db.commit()
