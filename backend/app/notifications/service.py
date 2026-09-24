"""The one place a notification is ever created.

Everything that wants to notify someone -- the admin endpoint today, an
automatic rule tomorrow -- goes through `send_notification`. That is the
whole point: when inactivity reminders or rank-drop alerts arrive, they
are new CALL SITES of this function, not a new system beside it.

Modelled directly on app/achievements/service.py's
check_and_grant_achievements: one function, safe to call defensively and
often, whose "don't do this twice" guarantee comes from a database
constraint rather than from callers remembering to check first.
"""

from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dates import utc_now
from app.models.notification import SOURCE_MANUAL, Notification
from app.models.user import User


def send_notification(
    db: Session,
    user: User,
    body: str,
    *,
    title: str | None = None,
    source: str = SOURCE_MANUAL,
    dedupe_key: str | None = None,
) -> Notification | None:
    """Puts one message in `user`'s inbox and returns it.

    `dedupe_key` is the idempotency handle an automatic sender uses: pass a
    key that describes exactly what is being reported ("inactive:7d:
    2026-09-24", "rank_drop:season_12") and this returns None instead of
    sending again if that same key already went to that same user. Manual
    messages pass nothing and are always sent.

    The pre-check below narrows the common case, but two simultaneous
    callers could both pass it -- UNIQUE(user_id, dedupe_key) is what
    actually decides at the database level. The insert runs in its own
    SAVEPOINT so a loser's IntegrityError rolls back only this insert and
    not the rest of the caller's transaction (an event site may have
    already written progress in the same request), and returns quietly, as
    if the message had already been sent. Same pattern, and same reasoning,
    as award_word_points_if_new.

    Deliberately does NOT commit: the caller owns the transaction, exactly
    like the achievements service, so an event site can grant points, write
    progress and notify in one atomic step.
    """
    text = body.strip()
    if not text:
        raise ValueError("Текст уведомления не может быть пустым")

    # Namespaced by source, so two different rules cannot collide on a
    # plain key like "2026-09-25" and silently suppress each other. Done
    # now because every stored key is still NULL -- doing it later would
    # mean migrating a unique constraint on live rows.
    stored_key = f"{source}:{dedupe_key}" if dedupe_key is not None else None

    if stored_key is not None:
        already = (
            db.query(Notification.id)
            .filter(Notification.user_id == user.id, Notification.dedupe_key == stored_key)
            .first()
        )
        if already is not None:
            return None

    notification = Notification(
        user_id=user.id,
        source=source,
        title=(title.strip() or None) if title else None,
        body=text,
        dedupe_key=stored_key,
    )
    try:
        with db.begin_nested():
            db.add(notification)
            db.flush()
    except IntegrityError:
        # Lost a race against a concurrent send of the same dedupe_key --
        # the message is in the inbox either way.
        return None
    return notification


def unread_count(db: Session, user: User) -> int:
    """How many messages the user has not opened yet -- what the bell's
    indicator is drawn from."""
    return (
        db.query(func.count(Notification.id))
        .filter(Notification.user_id == user.id, Notification.read_at.is_(None))
        .scalar()
        or 0
    )


def mark_all_read(db: Session, user: User) -> int:
    """Marks every unread message read. Returns how many were affected."""
    now = utc_now()
    affected = (
        db.query(Notification)
        .filter(Notification.user_id == user.id, Notification.read_at.is_(None))
        .update({Notification.read_at: now}, synchronize_session=False)
    )
    return affected or 0
