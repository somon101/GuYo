"""The user's own notification inbox, and the admin side that writes to it.

Both live here because they are two views of one table: the admin endpoint
creates a Notification through the same service any future automatic rule
will use, and the user endpoints only read and mark read.
"""

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin, get_current_user
from app.database import get_db
from app.models.notification import SOURCE_MANUAL, Notification
from app.models.user import User
from app.notifications import mark_all_read, send_notification, unread_count
from app.schemas.notification import (
    AdminNotificationOut,
    NotificationListOut,
    NotificationOut,
    NotificationSendIn,
    UnreadCountOut,
)

router = APIRouter(tags=["notifications"])

# A phone's notification list is read, not paged through; this is a sanity
# bound so one very old account cannot return thousands of rows at once.
INBOX_LIMIT = 200


def _out(notification: Notification) -> NotificationOut:
    return NotificationOut(
        id=notification.id,
        title=notification.title,
        body=notification.body,
        source=notification.source,
        is_read=notification.read_at is not None,
        read_at=notification.read_at,
        created_at=notification.created_at,
    )


def _admin_out(notification: Notification, login: str) -> AdminNotificationOut:
    return AdminNotificationOut(
        id=notification.id,
        title=notification.title,
        body=notification.body,
        source=notification.source,
        is_read=notification.read_at is not None,
        read_at=notification.read_at,
        created_at=notification.created_at,
        user_id=notification.user_id,
        user_login=login,
    )


# --- The user's own inbox ----------------------------------------------------


@router.get("/notifications", response_model=NotificationListOut)
def list_my_notifications(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """This user's messages, newest first, with the unread count the bell's
    indicator is drawn from -- one round trip, so the client never counts
    unread messages itself."""
    items = (
        db.query(Notification)
        .filter(Notification.user_id == user.id)
        .order_by(Notification.created_at.desc(), Notification.id.desc())
        .limit(INBOX_LIMIT)
        .all()
    )
    return NotificationListOut(unread_count=unread_count(db, user), items=[_out(n) for n in items])


@router.get("/notifications/unread-count", response_model=UnreadCountOut)
def get_unread_count(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Just the number behind the bell's dot. Its own endpoint so the app
    bar never has to pull the whole inbox to decide whether to show a
    dot."""
    return UnreadCountOut(unread_count=unread_count(db, user))


@router.post("/notifications/read-all", response_model=NotificationListOut)
def mark_all_notifications_read(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    mark_all_read(db, user)
    db.commit()
    items = (
        db.query(Notification)
        .filter(Notification.user_id == user.id)
        .order_by(Notification.created_at.desc(), Notification.id.desc())
        .limit(INBOX_LIMIT)
        .all()
    )
    return NotificationListOut(unread_count=unread_count(db, user), items=[_out(n) for n in items])


# --- Admin: write to one user ------------------------------------------------

admin_router = APIRouter(prefix="/admin/notifications", tags=["admin-notifications"])


@admin_router.post("", response_model=AdminNotificationOut, status_code=status.HTTP_201_CREATED)
def send_to_user(payload: NotificationSendIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Sends one message to one user.

    Goes through the same send_notification every future automatic rule
    will use -- this endpoint is a caller of that function, not a second
    way to create notifications. It passes no dedupe key, so an admin may
    deliberately send the same text again."""
    user = db.get(User, payload.user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    notification = send_notification(
        db,
        user,
        payload.body,
        title=payload.title,
        source=SOURCE_MANUAL,
    )
    if notification is None:
        # Only reachable for a deduped send, which a manual message never
        # is -- surfaced rather than silently reporting success.
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Уведомление уже было отправлено")
    db.commit()
    db.refresh(notification)
    return _admin_out(notification, user.login)


@admin_router.get("", response_model=list[AdminNotificationOut])
def list_sent_notifications(
    user_id: int | None = Query(None),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """What has been sent, newest first -- everything, or one user's
    thread when `user_id` is given. Includes automatically sent messages
    once rules exist, since they are the same rows."""
    query = db.query(Notification, User.login).join(User, User.id == Notification.user_id)
    if user_id is not None:
        query = query.filter(Notification.user_id == user_id)
    rows = query.order_by(Notification.created_at.desc(), Notification.id.desc()).limit(INBOX_LIMIT).all()
    return [_admin_out(notification, login) for notification, login in rows]
