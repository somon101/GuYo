"""The «Лента»: automatic cards, likes and ready-made comments, shown like on Instagram.

- Cards are made by the app's own events (a streak, learned words, an achievement, a duel won); nobody
  writes anything, people only react (a heart, or one ready-made phrase).
- Friends always see a card. Everybody else: the card is shown to a small group first (`reach`); when
  that group reacts well the group grows, when interest drops it stops growing. Old cards leave.
- The number of views is seen only by the author."""

from datetime import timedelta

from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dates import DUSHANBE_TZ, dushanbe_today, utc_now
from app.core.storage import url_for_key
from app.models.feed import FeedCard, FeedComment, FeedLike, FeedSeen
from app.models.friendship import Friendship
from app.models.social import FriendRequest
from app.models.user import User
from app.premium.service import effective_premium_user_ids
from app.social.friends import relation

# Ready-made comments: nobody types their own. The text is the key; the app shows it in the reader's language.
PHRASES = ["Молодец!", "Так держать!", "Огонь!", "Горжусь тобой", "Догоню тебя", "Вместе к цели"]
STREAK_MILESTONES = {3, 7, 14, 21, 30, 50, 75, 100, 150, 200, 300, 365}
LIFETIME = timedelta(days=7)  # an older card leaves the feed
FIRST_REACH = 30  # strangers a new card is shown to at first
GOOD_REACTION = 0.08  # (likes + comments) per view that earns a wider reach
MAX_REACH = 1_000_000
PAGE = 20
LIKERS_SHOWN = 8


class FeedError(Exception):
    """A refusal with a user-facing message."""


# --- Making cards (called by the app's events; never fail the caller) ----------------------


def post(db: Session, user: User, kind: str, data: dict, key: str, *, update: bool = False) -> FeedCard | None:
    try:
        with db.begin_nested():
            card = db.query(FeedCard).filter(FeedCard.dedupe_key == key).first()
            if card is not None:
                if update:
                    card.data = data
                    card.updated_at = utc_now()
                return card
            card = FeedCard(user_id=user.id, kind=kind, data=data, dedupe_key=key, reach=FIRST_REACH)
            db.add(card)
            db.flush()
            return card
    except Exception:
        return None


def post_streak(db: Session, user: User, days: int) -> None:
    if days in STREAK_MILESTONES:
        post(db, user, "streak", {"days": days}, f"streak:{user.id}:{days}")


def post_words_today(db: Session, user: User) -> None:
    """«Выучил(а) сегодня N слов»: one card per day, updated through the day (the day is Dushanbe's)."""
    try:
        from app.models.word_progress import WordProgress

        today = dushanbe_today()
        count = 0
        for (at,) in (
            db.query(WordProgress.mastered_at)
            .filter(WordProgress.user_id == user.id, WordProgress.mastered_at.isnot(None))
            .order_by(WordProgress.mastered_at.desc())
            .limit(200)
        ):
            if at.astimezone(DUSHANBE_TZ).date() == today:
                count += 1
        if count > 0:
            post(db, user, "words", {"count": count}, f"words:{user.id}:{today.isoformat()}", update=True)
    except Exception:
        pass


def post_achievement(db: Session, user: User, achievement_id: int, title: str) -> None:
    post(db, user, "achievement", {"achievement_id": achievement_id, "title": title}, f"achievement:{user.id}:{achievement_id}")


def post_duel_win(db: Session, user: User, duel_id: int, mine: int, theirs: int, against: str) -> None:
    post(db, user, "duel", {"mine": mine, "theirs": theirs, "against": against}, f"duel:{user.id}:{duel_id}")


def post_rank(db: Session, user: User, rank_name: str) -> None:
    post(db, user, "rank", {"rank": rank_name}, f"rank:{user.id}:{rank_name}")


# --- Reading -------------------------------------------------------------------------------


def _friend_ids(db: Session, user_id: int) -> set[int]:
    return {r[0] for r in db.query(Friendship.friend_id).filter(Friendship.user_id == user_id)}


def _score(card: FeedCard, now) -> float:
    age_hours = max(0.0, (now - card.created_at).total_seconds() / 3600)
    return (card.likes + 2 * card.comments + 1) / (age_hours + 2) ** 1.3


def _grow(card: FeedCard) -> None:
    """A card that has been shown to its whole group and was well received is shown to a wider one."""
    if card.views >= card.reach and card.reach < MAX_REACH:
        rate = (card.likes + card.comments) / max(card.views, 1)
        if rate >= GOOD_REACTION:
            card.reach = min(card.reach * 3, MAX_REACH)


def _person(user: User, premium: set[int]) -> dict:
    return {
        "user_id": user.id,
        "login": user.login,
        "avatar_url": url_for_key(user.avatar_key),
        "avatar_look": user.avatar_look,
        "is_premium": user.id in premium,
    }


def _cards_out(db: Session, me: User, cards: list[FeedCard], friends: set[int]) -> list[dict]:
    if not cards:
        return []
    ids = [c.id for c in cards]
    authors = {u.id: u for u in db.query(User).filter(User.id.in_({c.user_id for c in cards}))}
    liked = {r[0] for r in db.query(FeedLike.card_id).filter(FeedLike.user_id == me.id, FeedLike.card_id.in_(ids))}
    mine = {c.card_id: c.phrase for c in db.query(FeedComment).filter(FeedComment.user_id == me.id, FeedComment.card_id.in_(ids))}
    likers: dict[int, list[int]] = {i: [] for i in ids}
    for card_id, user_id in db.query(FeedLike.card_id, FeedLike.user_id).filter(FeedLike.card_id.in_(ids)).order_by(FeedLike.id.desc()):
        if len(likers[card_id]) < LIKERS_SHOWN:
            likers[card_id].append(user_id)
    last: dict[int, tuple[int, str]] = {}
    for c in db.query(FeedComment).filter(FeedComment.card_id.in_(ids)).order_by(FeedComment.id.desc()):
        last.setdefault(c.card_id, (c.user_id, c.phrase))
    people_ids = set(authors) | {u for ls in likers.values() for u in ls} | {u for u, _ in last.values()}
    people = {u.id: u for u in db.query(User).filter(User.id.in_(people_ids))}
    premium = effective_premium_user_ids(db, list(people))
    out = []
    for c in cards:
        author = authors.get(c.user_id)
        if author is None or author.deleted_at is not None:
            continue
        last_comment = last.get(c.id)
        out.append(
            {
                "id": c.id,
                "kind": c.kind,
                "data": c.data,
                "created_at": c.created_at,
                "updated_at": c.updated_at,
                "person": _person(author, premium),
                "is_mine": c.user_id == me.id,
                "is_friend": c.user_id in friends,
                "likes": c.likes,
                "comments": c.comments,
                "liked": c.id in liked,
                "my_comment": mine.get(c.id),
                "likers": [_person(people[u], premium) for u in likers[c.id] if u in people],
                "last_comment": None
                if last_comment is None or last_comment[0] not in people
                else {"person": _person(people[last_comment[0]], premium), "phrase": last_comment[1]},
                # Only the author sees how many people saw the card.
                "views": c.views if c.user_id == me.id else None,
            }
        )
    return out


def feed(db: Session, me: User, offset: int = 0) -> dict:
    now = utc_now()
    friends = _friend_ids(db, me.id)
    hidden = {r[0] for r in db.query(FeedSeen.card_id).filter(FeedSeen.user_id == me.id, FeedSeen.hidden.is_(True))}
    seen = {r[0] for r in db.query(FeedSeen.card_id).filter(FeedSeen.user_id == me.id)}
    private = {r[0] for r in db.query(User.id).filter(User.feed_friends_only.is_(True))}
    rows = (
        db.query(FeedCard)
        .join(User, User.id == FeedCard.user_id)
        .filter(FeedCard.created_at >= now - LIFETIME, User.deleted_at.is_(None))
        .order_by(FeedCard.id.desc())
        .limit(400)
        .all()
    )
    shown = []
    for c in rows:
        if c.id in hidden:
            continue
        is_friend = c.user_id in friends or c.user_id == me.id
        if not is_friend and (c.user_id in private or (c.views >= c.reach and c.id not in seen)):
            continue
        shown.append((0 if is_friend else 1, -_score(c, now), c))
    shown.sort(key=lambda t: (t[0], t[1]))
    page = [c for _, _, c in shown[offset : offset + PAGE]]
    # Seeing counts (once per person); a card shown to its whole group stops spreading unless liked.
    for c in page:
        if c.user_id != me.id and c.id not in seen:
            try:
                with db.begin_nested():
                    db.add(FeedSeen(card_id=c.id, user_id=me.id))
                    db.flush()
                c.views += 1
            except IntegrityError:
                pass
    for c in page:
        _grow(c)
    db.flush()
    return {"cards": _cards_out(db, me, page, friends), "has_more": len(shown) > offset + PAGE, "phrases": PHRASES}


def _card(db: Session, card_id: int) -> FeedCard:
    card = db.get(FeedCard, card_id)
    if card is None:
        raise FeedError("Карточка не найдена")
    return card


def _one(db: Session, me: User, card: FeedCard) -> dict:
    db.flush()
    return _cards_out(db, me, [card], _friend_ids(db, me.id))[0]


def set_like(db: Session, me: User, card_id: int, on: bool) -> dict:
    card = _card(db, card_id)
    existing = db.query(FeedLike).filter(FeedLike.card_id == card.id, FeedLike.user_id == me.id).first()
    if on and existing is None:
        db.add(FeedLike(card_id=card.id, user_id=me.id))
        card.likes += 1
    elif not on and existing is not None:
        db.delete(existing)
        card.likes = max(0, card.likes - 1)
    return _one(db, me, card)


def set_comment(db: Session, me: User, card_id: int, phrase: str | None) -> dict:
    card = _card(db, card_id)
    existing = db.query(FeedComment).filter(FeedComment.card_id == card.id, FeedComment.user_id == me.id).first()
    if phrase is None:
        if existing is not None:
            db.delete(existing)
            card.comments = max(0, card.comments - 1)
    else:
        if phrase not in PHRASES:
            raise FeedError("Такой готовой фразы нет")
        if existing is None:
            db.add(FeedComment(card_id=card.id, user_id=me.id, phrase=phrase))
            card.comments += 1
        else:
            existing.phrase = phrase
    return _one(db, me, card)


def hide(db: Session, me: User, card_id: int) -> None:
    card = _card(db, card_id)
    seen = db.query(FeedSeen).filter(FeedSeen.card_id == card.id, FeedSeen.user_id == me.id).first()
    if seen is None:
        db.add(FeedSeen(card_id=card.id, user_id=me.id, hidden=True))
    else:
        seen.hidden = True


def likers(db: Session, me: User, card_id: int) -> list[dict]:
    card = _card(db, card_id)
    rows = (
        db.query(User)
        .join(FeedLike, FeedLike.user_id == User.id)
        .filter(FeedLike.card_id == card.id, User.deleted_at.is_(None))
        .order_by(FeedLike.id.desc())
        .limit(200)
        .all()
    )
    premium = effective_premium_user_ids(db, [u.id for u in rows])
    return [{**_person(u, premium), "relation": relation(db, me.id, u.id)} for u in rows]


def suggestions(db: Session, me: User, limit: int = 8) -> list[dict]:
    """«Возможно, вы знакомы»: friends of friends first (with how many), then people of the same rank
    who study every day, then simply active people. Never someone already a friend or asked."""
    friends = _friend_ids(db, me.id)
    skip = friends | {me.id}
    skip |= {r[0] for r in db.query(FriendRequest.to_id).filter(FriendRequest.from_id == me.id)}
    skip |= {r[0] for r in db.query(FriendRequest.from_id).filter(FriendRequest.to_id == me.id)}
    reasons: dict[int, tuple[int, str]] = {}
    if friends:
        counts = (
            db.query(Friendship.friend_id, func.count(Friendship.id))
            .filter(Friendship.user_id.in_(friends), ~Friendship.friend_id.in_(skip))
            .group_by(Friendship.friend_id)
            .order_by(func.count(Friendship.id).desc())
            .limit(limit)
        )
        for uid, n in counts:
            reasons[uid] = (n, "mutual")
    if len(reasons) < limit:
        from app.models.rating import UserRating

        mine = db.query(UserRating.total_points).filter(UserRating.user_id == me.id).scalar() or 0
        near = (
            db.query(UserRating.user_id)
            .join(User, User.id == UserRating.user_id)
            .filter(User.deleted_at.is_(None), ~UserRating.user_id.in_(skip | set(reasons)))
            .order_by(func.abs(UserRating.total_points - mine), UserRating.user_id)
            .limit(limit - len(reasons))
        )
        for (uid,) in near:
            reasons[uid] = (0, "near")
    people = {u.id: u for u in db.query(User).filter(User.id.in_(list(reasons)))}
    premium = effective_premium_user_ids(db, list(people))
    out = [
        {**_person(people[uid], premium), "reason": kind, "count": n}
        for uid, (n, kind) in sorted(reasons.items(), key=lambda kv: -kv[1][0])
        if uid in people
    ]
    return out[:limit]
