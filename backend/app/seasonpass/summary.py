"""The recap of a finished season: what a person got out of it."""

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.achievement import UserActivityDay
from app.models.rating import SEASON_COMPLETED, Rank, Season, SeasonHistory
from app.models.season_pass import PassClaim, PassXpEvent, UserCosmetic
from app.models.user import User
from app.models.word_progress import WordProgress
from app.core.dates import DUSHANBE_TZ
from app.seasonpass.service import level_for_xp, season_pass, total_xp


def latest_season_for(db: Session, user_id: int) -> Season | None:
    """The most recently finished season the person earned XP in."""
    return (
        db.query(Season)
        .join(PassXpEvent, PassXpEvent.season_id == Season.id)
        .filter(Season.status == SEASON_COMPLETED, PassXpEvent.user_id == user_id)
        .order_by(Season.ends_at.desc(), Season.id.desc())
        .first()
    )


def season_summary(db: Session, user: User) -> dict | None:
    season = latest_season_for(db, user.id)
    if season is None:
        return None
    levels = season_pass(db, season).definition["levels"]
    xp = total_xp(db, user.id, season.id)
    level, _, _ = level_for_xp(levels, xp)
    start, end = season.starts_at, season.ends_at
    words = (
        db.query(func.count(WordProgress.id))
        .filter(WordProgress.user_id == user.id, WordProgress.mastered_at >= start, WordProgress.mastered_at < end)
        .scalar()
    )
    days = (
        db.query(func.count(UserActivityDay.id))
        .filter(
            UserActivityDay.user_id == user.id,
            UserActivityDay.activity_date >= start.astimezone(DUSHANBE_TZ).date(),
            UserActivityDay.activity_date <= end.astimezone(DUSHANBE_TZ).date(),
        )
        .scalar()
    )
    history = db.query(SeasonHistory).filter_by(user_id=user.id, season_id=season.id).first()
    rank = db.get(Rank, history.rank_id) if history is not None and history.rank_id else None
    cosmetics = db.query(UserCosmetic).filter_by(user_id=user.id, season_id=season.id).all()
    claimed = db.query(func.count(PassClaim.id)).filter_by(user_id=user.id, season_id=season.id).scalar()
    return {
        "season_id": season.id,
        "season_name": season.name,
        "season_name_tg": season.name_tg,
        "season_name_uz": season.name_uz,
        "starts_at": start,
        "ends_at": end,
        "xp": xp,
        "level": level,
        "max_level": len(levels),
        "words_learned": words or 0,
        "active_days": days or 0,
        "rewards_claimed": claimed or 0,
        "rank_name": rank.name if rank else None,
        "season_points": history.points if history is not None else None,
        "badges": [c.key for c in cosmetics if c.kind == "badge"],
        "titles": [{"text": c.label, "text_tg": c.label_tg, "text_uz": c.label_uz} for c in cosmetics if c.kind == "title"],
    }
