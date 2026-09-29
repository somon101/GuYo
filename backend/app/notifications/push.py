"""Push delivery for inbox notifications, through Firebase Cloud Messaging.

Push is a second delivery channel for the SAME Notification rows, not a
separate kind of message: send_notification queues a push for every
notification it creates, and nothing else sends pushes.

A push only goes out once the notification is really committed -- the
caller owns the transaction, and a push for a rolled-back row would be a
message the inbox never shows. Delivery then runs on a background thread
so no request waits on Google.
"""

import json
import logging
import threading
from datetime import datetime, time

from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account
from sqlalchemy import event, func
from sqlalchemy.orm import Session

from app.config import get_settings
from app.core.dates import DUSHANBE_TZ, dushanbe_today
from app.models.notification import Notification, PushToken

logger = logging.getLogger(__name__)

_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_PENDING_KEY = "pending_pushes"

# Sources that can fire several times a day for one person. Every message
# still reaches the inbox; only the first of the day also rings the phone.
DAILY_CAPPED_SOURCES = {"rank_move"}

_client_lock = threading.Lock()
_client: tuple[AuthorizedSession, str] | None = None


def _fcm_client() -> tuple[AuthorizedSession, str] | None:
    """(authorized HTTP session, Firebase project id), or None when no
    service-account key is configured -- push is then simply off."""
    global _client
    raw = get_settings().firebase_service_account_json
    if not raw:
        return None
    with _client_lock:
        if _client is None:
            info = json.loads(raw)
            credentials = service_account.Credentials.from_service_account_info(info, scopes=[_SCOPE])
            _client = (AuthorizedSession(credentials), info["project_id"])
        return _client


def queue_push(db: Session, notification: Notification) -> None:
    db.info.setdefault(_PENDING_KEY, []).append(
        (notification.user_id, notification.title, notification.body, notification.source)
    )


@event.listens_for(Session, "after_commit")
def _deliver_after_commit(session: Session) -> None:
    # Also fires when a SAVEPOINT is released (send_notification uses one);
    # only the outermost commit means the rows are really saved.
    if session.in_nested_transaction():
        return
    pending = session.info.pop(_PENDING_KEY, None)
    if not pending:
        return
    try:
        if _fcm_client() is not None:
            threading.Thread(target=_deliver, args=(pending,), daemon=True).start()
    except Exception:
        # The data is already committed; a broken push setup must not turn
        # that into an error for whoever committed it.
        logger.exception("could not start push delivery")


@event.listens_for(Session, "after_rollback")
def _drop_after_rollback(session: Session) -> None:
    # A rolled-back SAVEPOINT (a deduped send losing a race) must not drop
    # the pushes queued earlier in the same, still-open transaction.
    if not session.in_nested_transaction():
        session.info.pop(_PENDING_KEY, None)


def _already_pushed_today(db: Session, user_id: int, source: str) -> bool:
    day_start = datetime.combine(dushanbe_today(), time.min, tzinfo=DUSHANBE_TZ)
    sent_today = (
        db.query(func.count(Notification.id))
        .filter(Notification.user_id == user_id, Notification.source == source, Notification.created_at >= day_start)
        .scalar()
    )
    return sent_today > 1  # the one just committed counts itself


def _deliver(pending: list[tuple[int, str | None, str, str]]) -> None:
    from app.database import SessionLocal

    client = _fcm_client()
    if client is None:
        return
    http, project_id = client
    url = f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"

    db = SessionLocal()
    try:
        for user_id, title, body, source in pending:
            if source in DAILY_CAPPED_SOURCES and _already_pushed_today(db, user_id, source):
                continue
            for push_token in db.query(PushToken).filter(PushToken.user_id == user_id).all():
                message = {
                    "token": push_token.token,
                    "notification": {"title": title or "GuYo", "body": body},
                    "data": {"source": source},
                    "android": {"priority": "high"},
                }
                try:
                    response = http.post(url, json={"message": message}, timeout=10)
                except Exception:
                    logger.exception("push to user %s failed", user_id)
                    continue
                if response.status_code == 200:
                    continue
                if response.status_code == 404 or "UNREGISTERED" in response.text:
                    # The app was uninstalled or the token rotated.
                    db.delete(push_token)
                    db.commit()
                else:
                    logger.warning("push to user %s: %s %s", user_id, response.status_code, response.text[:300])
    except Exception:
        logger.exception("push delivery failed")
    finally:
        db.close()
