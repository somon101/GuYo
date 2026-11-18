"""What other people see of a person: the «Витрина» profile (achievements, team, the week, habits).

Built only from data the app already has (answers, rating, achievements, the team). Never shows an
e-mail, a phone number or a surname."""

from collections import Counter
from datetime import timedelta

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.dates import DUSHANBE_TZ, dushanbe_today
from app.core.storage import url_for_key
from app.models.achievement import Achievement, UserAchievement
from app.models.dictionary import Dictionary
from app.models.word_progress import WordProgress
from app.models.quest import Quest, UserQuestWordDay
from app.models.rating import UserWordPoints
from app.models.team import Team, TeamMember
from app.models.user import User
from app.models.word import Word
from app.models.word_attempt import WordAttempt
from app.premium.service import effective_premium_user_ids
from app.rating.service import current_rank_for_points, get_or_create_user_rating
from app.social.friends import relation

WEEKDAYS = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]


def _habits(db: Session, user_id: int) -> dict:
    rows = (
        db.query(WordAttempt.is_correct, WordAttempt.duration_ms, WordAttempt.created_at)
        .filter(WordAttempt.user_id == user_id)
        .order_by(WordAttempt.id.desc())
        .limit(2000)
        .all()
    )
    if not rows:
        return {"hours": None, "best_day": None, "accuracy": None, "avg_answer": None}
    by_hour: Counter = Counter()
    by_day: Counter = Counter()
    durations = []
    for ok, ms, at in rows:
        local = at.astimezone(DUSHANBE_TZ)
        by_hour[local.hour // 2] += 1
        by_day[local.weekday()] += 1
        if ms:
            durations.append(min(ms, 120_000))
    slot = by_hour.most_common(1)[0][0]
    return {
        # The two-hour window the person studies in most often.
        "hours": f"{slot * 2}–{slot * 2 + 2}",
        "best_day": by_day.most_common(1)[0][0],  # 0 = Monday
        "accuracy": round(sum(1 for ok, _, _ in rows if ok) * 100 / len(rows)),
        "avg_answer": round(sum(durations) / len(durations) / 1000, 1) if durations else None,
    }


def _week_points(db: Session, user_id: int) -> list[int]:
    """Points for each of the last 7 days (oldest first, today last), as on the rating screens."""
    today = dushanbe_today()
    start = today - timedelta(days=6)
    per_day: Counter = Counter()
    for pts, at in db.query(UserWordPoints.points_awarded, UserWordPoints.awarded_at).filter(UserWordPoints.user_id == user_id):
        d = at.astimezone(DUSHANBE_TZ).date()
        if d >= start:
            per_day[d] += pts
    for reward, used in (
        db.query(Quest.reward_points, UserQuestWordDay.used_date)
        .join(Quest, Quest.id == UserQuestWordDay.quest_id)
        .filter(UserQuestWordDay.user_id == user_id, UserQuestWordDay.used_date >= start)
    ):
        per_day[used] += reward
    return [per_day.get(start + timedelta(days=i), 0) for i in range(7)]


def _team(db: Session, me: User, user_id: int) -> dict | None:
    from app.models.social import TeamJoinRequest
    from app.seasonpass.teams import team_size_cap

    member = db.query(TeamMember).filter(TeamMember.user_id == user_id).first()
    if member is None:
        return None
    team = db.get(Team, member.team_id)
    count = db.query(func.count(TeamMember.id)).filter(TeamMember.team_id == team.id).scalar()
    mine = db.query(TeamMember.team_id).filter(TeamMember.user_id == me.id).scalar()
    asked = (
        db.query(TeamJoinRequest.id)
        .filter(TeamJoinRequest.team_id == team.id, TeamJoinRequest.user_id == me.id, TeamJoinRequest.declined_at.is_(None))
        .first()
        is not None
    )
    return {
        "id": team.id,
        "name": team.name,
        "is_open": team.is_open,
        "members": count,
        "capacity": team_size_cap(db),
        "is_mine": mine == team.id,
        "requested": asked,
    }


def public_profile(db: Session, me: User, user_id: int) -> dict | None:
    user = db.get(User, user_id)
    if user is None or user.deleted_at is not None:
        return None
    lang = me.ui_language
    earned = {
        r[0]
        for r in db.query(UserAchievement.achievement_id).filter(UserAchievement.user_id == user.id)
    }
    shelf = []
    for a in db.query(Achievement).order_by(Achievement.order, Achievement.id).all():
        if not a.enabled and a.id not in earned:
            continue
        got = a.id in earned
        if not got and a.visibility == "hidden":
            continue  # a hidden one stays hidden until it is earned
        title = a.localized(lang)[0]
        shelf.append({"id": a.id, "title": title, "icon_url": url_for_key(a.icon_key), "color": a.color, "earned": got})
    rating = get_or_create_user_rating(db, user.id)
    rank = current_rank_for_points(db, rating.total_points)
    studying = [
        r[0]
        for r in db.query(Dictionary.name)
        .join(Word, Word.dictionary_id == Dictionary.id)
        .join(WordProgress, WordProgress.word_id == Word.id)
        .filter(WordProgress.user_id == user.id, WordProgress.mastered_at.isnot(None))
        .group_by(Dictionary.id, Dictionary.name)
        .order_by(func.count(WordProgress.id).desc())
        .limit(3)
    ]
    from app.seasonpass.cosmetics import badge_keys, frame_keys

    week = _week_points(db, user.id)
    return {
        "user_id": user.id,
        "login": user.login,
        "avatar_url": url_for_key(user.avatar_key),
        "avatar_look": user.avatar_look,
        "is_premium": user.id in effective_premium_user_ids(db, [user.id]),
        "badge": badge_keys(db, [user.id]).get(user.id),
        "frame": frame_keys(db, [user.id]).get(user.id),
        "rank": None if rank is None else rank.name,
        "total_points": rating.total_points,
        "relation": relation(db, me.id, user.id),
        "achievements_earned": len(earned & {s_id for s_id in (x["id"] for x in shelf)}),
        "achievements_total": len(shelf),
        "achievements": shelf,
        "team": _team(db, me, user.id),
        "week_points": week,
        "week_total": sum(week),
        "habits": _habits(db, user.id),
        "studying": studying,
    }
