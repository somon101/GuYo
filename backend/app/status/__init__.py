"""Leaderboard statuses -- see app/models/status.py."""

from sqlalchemy.orm import Session

from app.core.storage import url_for_key
from app.models.status import StatusEmoji, StatusPhrase
from app.models.user import User
from app.schemas.status import MyStatusOut


def statuses_for(db: Session, users: list[User]) -> dict[int, tuple[str | None, str | None]]:
    """{user_id: (emoji_url, phrase_text)} for every user that shows a
    status, in two queries however many users -- what the leaderboard
    needs for its up to 100 rows. A switched-off item shows as unset."""
    emoji_ids = {u.status_emoji_id for u in users if u.status_emoji_id}
    phrase_ids = {u.status_phrase_id for u in users if u.status_phrase_id}
    emojis = {
        e.id: url_for_key(e.image_key)
        for e in db.query(StatusEmoji).filter(StatusEmoji.id.in_(emoji_ids), StatusEmoji.enabled.is_(True)).all()
    } if emoji_ids else {}
    phrases = {
        p.id: p.text
        for p in db.query(StatusPhrase).filter(StatusPhrase.id.in_(phrase_ids), StatusPhrase.enabled.is_(True)).all()
    } if phrase_ids else {}
    out = {}
    for u in users:
        url, text = emojis.get(u.status_emoji_id), phrases.get(u.status_phrase_id)
        if url or text:
            out[u.id] = (url, text)
    return out


def my_status(db: Session, user: User) -> MyStatusOut:
    emoji = db.get(StatusEmoji, user.status_emoji_id) if user.status_emoji_id else None
    phrase = db.get(StatusPhrase, user.status_phrase_id) if user.status_phrase_id else None
    if emoji is not None and not emoji.enabled:
        emoji = None
    if phrase is not None and not phrase.enabled:
        phrase = None
    return MyStatusOut(
        emoji_id=emoji.id if emoji else None,
        emoji_url=url_for_key(emoji.image_key) if emoji else None,
        phrase_id=phrase.id if phrase else None,
        text=phrase.text if phrase else None,
    )
