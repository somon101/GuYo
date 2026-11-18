"""Friend requests: «Добавить в друзья» asks, the other person accepts or declines.

Adding by the 9-digit ID or a QR code (app/routers/rating.py) stays instant: the two people are
standing together. A request is for everyone else (the feed, a profile, the list of those who liked)."""

from sqlalchemy.orm import Session

from app.core.storage import url_for_key
from app.models.friendship import Friendship
from app.models.social import FriendRequest
from app.models.user import User

PENDING_MAX = 100  # unanswered requests one person may have out at once


class FriendError(Exception):
    """A refusal with a user-facing message."""


_TEXTS = {
    "ask": {
        "ru": ("Запрос в друзья", "{who} хочет добавить вас в друзья."),
        "tg": ("Дархости дӯстӣ", "{who} мехоҳад шуморо ба дӯстон илова кунад."),
        "uz": ("Do‘st bo‘lish so‘rovi", "{who} sizni do‘st sifatida qo‘shmoqchi."),
        "en": ("Friend request", "{who} wants to add you as a friend."),
    },
    "accepted": {
        "ru": ("Вы теперь друзья", "{who} принял(а) ваш запрос в друзья."),
        "tg": ("Шумо акнун дӯстед", "{who} дархости дӯстии шуморо қабул кард."),
        "uz": ("Endi do‘stsiz", "{who} do‘stlik so‘rovingizni qabul qildi."),
        "en": ("You are friends now", "{who} accepted your friend request."),
    },
}


def _notify(db: Session, user: User, kind: str, key: str, **fields) -> None:
    try:
        from app.notifications import send_notification

        lang = user.ui_language if user.ui_language in ("ru", "tg", "uz", "en") else "ru"
        title, body = _TEXTS[kind][lang]
        send_notification(db, user, body.format(**fields), title=title, source="friend", dedupe_key=key)
    except Exception:  # a message is a courtesy; never fail the action over it
        pass


def is_friend(db: Session, a: int, b: int) -> bool:
    return db.query(Friendship.id).filter(Friendship.user_id == a, Friendship.friend_id == b).first() is not None


def relation(db: Session, me: int, other: int) -> str:
    """How `other` stands to `me`: self | friend | sent (I asked) | received (they asked) | none."""
    if me == other:
        return "self"
    if is_friend(db, me, other):
        return "friend"
    if db.query(FriendRequest.id).filter(FriendRequest.from_id == me, FriendRequest.to_id == other).first():
        return "sent"
    if db.query(FriendRequest.id).filter(FriendRequest.from_id == other, FriendRequest.to_id == me).first():
        return "received"
    return "none"


def _make_friends(db: Session, a: int, b: int) -> None:
    for x, y in ((a, b), (b, a)):
        if not is_friend(db, x, y):
            db.add(Friendship(user_id=x, friend_id=y))
    db.query(FriendRequest).filter(
        ((FriendRequest.from_id == a) & (FriendRequest.to_id == b)) | ((FriendRequest.from_id == b) & (FriendRequest.to_id == a))
    ).delete(synchronize_session=False)
    db.flush()


def _person(db: Session, user_id: int) -> User:
    other = db.get(User, user_id)
    if other is None or other.deleted_at is not None:
        raise FriendError("Пользователь не найден")
    return other


def send_request(db: Session, user: User, other_id: int) -> str:
    """Asks `other_id` to be friends. When they have already asked you, you are friends at once.
    Returns the new relation (sent | friend)."""
    other = _person(db, other_id)
    state = relation(db, user.id, other.id)
    if state == "self":
        raise FriendError("Это вы")
    if state == "friend":
        raise FriendError("Вы уже друзья")
    if state == "sent":
        return "sent"
    if state == "received":
        _make_friends(db, user.id, other.id)
        _notify(db, other, "accepted", f"friend-accepted:{user.id}:{other.id}", who=user.login)
        return "friend"
    if db.query(FriendRequest.id).filter(FriendRequest.from_id == user.id).count() >= PENDING_MAX:
        raise FriendError("Слишком много неотвеченных запросов")
    db.add(FriendRequest(from_id=user.id, to_id=other.id))
    db.flush()
    _notify(db, other, "ask", f"friend-ask:{user.id}:{other.id}", who=user.login)
    return "sent"


def cancel_request(db: Session, user: User, other_id: int) -> None:
    db.query(FriendRequest).filter(FriendRequest.from_id == user.id, FriendRequest.to_id == other_id).delete(
        synchronize_session=False
    )


def accept(db: Session, user: User, from_id: int) -> None:
    if db.query(FriendRequest.id).filter(FriendRequest.from_id == from_id, FriendRequest.to_id == user.id).first() is None:
        raise FriendError("Запрос не найден")
    other = _person(db, from_id)
    _make_friends(db, user.id, other.id)
    _notify(db, other, "accepted", f"friend-accepted:{user.id}:{other.id}", who=user.login)


def decline(db: Session, user: User, from_id: int) -> None:
    db.query(FriendRequest).filter(FriendRequest.from_id == from_id, FriendRequest.to_id == user.id).delete(
        synchronize_session=False
    )


def requests_state(db: Session, user: User) -> dict:
    """The requests waiting for the person's answer and the ones they have sent."""

    def rows(own_col, other_col):
        found = (
            db.query(FriendRequest, User)
            .join(User, User.id == other_col)
            .filter(own_col == user.id, User.deleted_at.is_(None))
            .order_by(FriendRequest.id.desc())
            .all()
        )
        return [
            {"user_id": u.id, "public_id": u.public_id, "login": u.login, "avatar_url": url_for_key(u.avatar_key)}
            for _, u in found
        ]

    return {
        "incoming": rows(FriendRequest.to_id, FriendRequest.from_id),
        "outgoing": rows(FriendRequest.from_id, FriendRequest.to_id),
    }
