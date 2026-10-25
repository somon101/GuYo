"""Badges and titles: what the season pass can give besides points, and what a
person wears. A badge is an icon from a fixed set (its look is drawn by the
app); a title is text. Both are kept for good once earned."""

from sqlalchemy.orm import Session

from app.models.season_pass import CosmeticDef, UserCosmetic
from app.models.user import User



def label_for(item, lang: str | None) -> str:
    """The text in the person's interface language, Russian as the fallback."""
    if isinstance(item, dict):
        ru, tg, uz = item.get("text"), item.get("text_tg"), item.get("text_uz")
    else:
        ru, tg, uz = item.label, item.label_tg, item.label_uz
    if lang == "tg" and tg:
        return tg
    if lang == "uz" and uz:
        return uz
    return ru or ""


def def_label(db: Session, key: str, lang: str | None) -> str | None:
    """The catalog name of a frame/badge/title in the person's language."""
    row = db.get(CosmeticDef, int(key)) if str(key).isdigit() else None
    if row is None:
        return None
    if lang == "tg" and row.name_tg:
        return row.name_tg
    if lang == "uz" and row.name_uz:
        return row.name_uz
    return row.name


def grant(db: Session, user: User, reward: dict, season) -> UserCosmetic | None:
    """Puts a badge/title reward into the person's collection (once) and wears
    it if they wear nothing of that kind yet. Does not commit."""
    kind = reward["type"]
    key = str(reward.get("key") or "")
    label = reward.get("text") or ""
    if not label and key.isdigit():
        definition = db.get(CosmeticDef, int(key))
        label = (definition.name if definition else "") or ""
    existing = (
        db.query(UserCosmetic)
        .filter(
            UserCosmetic.user_id == user.id,
            UserCosmetic.kind == kind,
            UserCosmetic.key == key,
            UserCosmetic.label == label,
            UserCosmetic.season_id == (season.id if season else None),
        )
        .first()
    )
    if existing is not None:
        return existing
    item = UserCosmetic(
        user_id=user.id,
        kind=kind,
        key=key,
        label=label,
        label_tg=reward.get("text_tg"),
        label_uz=reward.get("text_uz"),
        season_id=season.id if season else None,
        season_name=season.name if season else None,
    )
    db.add(item)
    db.flush()
    if kind == "badge" and user.equipped_badge_id is None:
        user.equipped_badge_id = item.id
    if kind == "title" and user.equipped_title_id is None:
        user.equipped_title_id = item.id
    if kind == "frame" and user.equipped_frame_id is None:
        user.equipped_frame_id = item.id
    db.flush()
    return item


def collection(db: Session, user: User) -> dict:
    items = db.query(UserCosmetic).filter(UserCosmetic.user_id == user.id).order_by(UserCosmetic.id.desc()).all()

    def out(c: UserCosmetic) -> dict:
        return {
            "id": c.id,
            "kind": c.kind,
            "key": c.key,
            "label": label_for(c, user.ui_language),
            "season_name": c.season_name,
        }

    return {
        "badges": [out(c) for c in items if c.kind == "badge"],
        "titles": [out(c) for c in items if c.kind == "title"],
        "frames": [out(c) for c in items if c.kind == "frame"],
        "equipped_badge_id": user.equipped_badge_id,
        "equipped_title_id": user.equipped_title_id,
        "equipped_frame_id": user.equipped_frame_id,
    }


class CosmeticError(Exception):
    pass


def equip(db: Session, user: User, badge_id: int | None, title_id: int | None, frame_id=...) -> None:
    """Sets what the person wears (None takes it off). Only things they own.
    `frame_id` left out (older apps) keeps the frame as it is."""
    for kind, item_id in (("badge", badge_id), ("title", title_id), ("frame", None if frame_id is ... else frame_id)):
        if item_id is None:
            continue
        owned = (
            db.query(UserCosmetic.id)
            .filter(UserCosmetic.id == item_id, UserCosmetic.user_id == user.id, UserCosmetic.kind == kind)
            .first()
        )
        if owned is None:
            raise CosmeticError("Этой награды нет в вашей коллекции")
    user.equipped_badge_id = badge_id
    user.equipped_title_id = title_id
    if frame_id is not ...:
        user.equipped_frame_id = frame_id
    db.flush()


def title_key(db: Session, user: User) -> str | None:
    """The key (picture id) of the title ribbon the person wears, if it has one."""
    title = db.get(UserCosmetic, user.equipped_title_id) if user.equipped_title_id else None
    return (title.key or None) if title else None


def worn(db: Session, user: User) -> tuple[str | None, str | None]:
    """(badge key, title text in the person's language) the person wears."""
    badge = db.get(UserCosmetic, user.equipped_badge_id) if user.equipped_badge_id else None
    title = db.get(UserCosmetic, user.equipped_title_id) if user.equipped_title_id else None
    return (badge.key if badge else None, label_for(title, user.ui_language) if title else None)


def badge_keys(db: Session, user_ids: list[int]) -> dict[int, str]:
    """user id -> the key of the badge they wear, for a whole list at once."""
    if not user_ids:
        return {}
    rows = (
        db.query(User.id, UserCosmetic.key)
        .join(UserCosmetic, UserCosmetic.id == User.equipped_badge_id)
        .filter(User.id.in_(user_ids))
        .all()
    )
    return {uid: key for uid, key in rows}


def frame_keys(db: Session, user_ids: list[int]) -> dict[int, str]:
    """user id -> the key of the avatar frame they wear, for a whole list at once."""
    if not user_ids:
        return {}
    rows = (
        db.query(User.id, UserCosmetic.key)
        .join(UserCosmetic, UserCosmetic.id == User.equipped_frame_id)
        .filter(User.id.in_(user_ids))
        .all()
    )
    return {uid: key for uid, key in rows}
