"""Teams: friends working on shared goals.

A goal's progress is never stored: it is counted from the season's XP ledger
(PassXpEvent), over every member, from the moment each of them joined. So it
cannot drift from what people actually did, and a member's share is the same
count grouped by person."""

from datetime import datetime

from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dates import utc_now
from app.models.friendship import Friendship
from app.models.rating import Season
from app.models.season_pass import PassClaim, PassXpEvent
from app.models.team import Team, TeamInvite, TeamMember
from app.models.user import User
from app.seasonpass.service import (
    METRICS,
    PassError,
    _give,
    _record_claim,
    award_xp,
    get_pass_settings,
    season_pass,
    week_bounds,
)

NAME_MIN, NAME_MAX = 3, 24
PENDING_INVITES_MAX = 10


class TeamError(PassError):
    """A refusal with a user-facing message."""


# --- Membership --------------------------------------------------------------


def membership(db: Session, user: User) -> TeamMember | None:
    return db.query(TeamMember).filter(TeamMember.user_id == user.id).first()


def team_size_cap(db: Session) -> int:
    return max(2, get_pass_settings(db).team_size)


def members_of(db: Session, team: Team) -> list[TeamMember]:
    return db.query(TeamMember).filter(TeamMember.team_id == team.id).order_by(TeamMember.joined_at, TeamMember.id).all()


def _clean_name(name: str) -> str:
    name = " ".join((name or "").split())
    if not (NAME_MIN <= len(name) <= NAME_MAX):
        raise TeamError(f"Название команды: от {NAME_MIN} до {NAME_MAX} символов")
    return name


def _name_free(db: Session, name: str, exclude_id: int | None = None) -> None:
    query = db.query(Team.id).filter(func.lower(Team.name) == name.lower())
    if exclude_id is not None:
        query = query.filter(Team.id != exclude_id)
    if query.first() is not None:
        raise TeamError("Команда с таким названием уже есть")


def _add_member(db: Session, team: Team, user: User) -> None:
    if len(members_of(db, team)) >= team_size_cap(db):
        raise TeamError("В команде нет свободных мест")
    try:
        with db.begin_nested():
            db.add(TeamMember(team_id=team.id, user_id=user.id))
            db.flush()
    except IntegrityError:
        raise TeamError("Вы уже состоите в команде") from None
    # Whatever invitations the person had are settled by joining.
    db.query(TeamInvite).filter(TeamInvite.user_id == user.id).delete(synchronize_session=False)


def create_team(db: Session, user: User, name: str, is_open: bool) -> Team:
    if membership(db, user) is not None:
        raise TeamError("Вы уже состоите в команде")
    name = _clean_name(name)
    _name_free(db, name)
    team = Team(name=name, owner_id=user.id, is_open=is_open)
    db.add(team)
    db.flush()
    _add_member(db, team, user)
    return team


def update_team(db: Session, user: User, team: Team, name: str | None, is_open: bool | None) -> None:
    if team.owner_id != user.id:
        raise TeamError("Это может только создатель команды")
    if name is not None:
        name = _clean_name(name)
        _name_free(db, name, exclude_id=team.id)
        team.name = name
    if is_open is not None:
        team.is_open = is_open
    db.flush()


def _is_friend(db: Session, user_id: int, other_id: int) -> bool:
    return (
        db.query(Friendship.id).filter(Friendship.user_id == user_id, Friendship.friend_id == other_id).first()
        is not None
    )


def invite(db: Session, owner: User, team: Team, friend_id: int) -> TeamInvite:
    if team.owner_id != owner.id:
        raise TeamError("Приглашать может только создатель команды")
    friend = db.get(User, friend_id)
    if friend is None or friend.deleted_at is not None or not _is_friend(db, owner.id, friend_id):
        raise TeamError("Пригласить можно только друга")
    if db.query(TeamMember.id).filter(TeamMember.user_id == friend_id).first() is not None:
        raise TeamError("Этот человек уже состоит в команде")
    if len(members_of(db, team)) >= team_size_cap(db):
        raise TeamError("В команде нет свободных мест")
    if db.query(TeamInvite.id).filter(TeamInvite.team_id == team.id, TeamInvite.user_id == friend_id).first():
        raise TeamError("Приглашение уже отправлено")
    if db.query(func.count(TeamInvite.id)).filter(TeamInvite.team_id == team.id).scalar() >= PENDING_INVITES_MAX:
        raise TeamError("Слишком много неотвеченных приглашений")
    item = TeamInvite(team_id=team.id, user_id=friend_id, invited_by=owner.id)
    db.add(item)
    db.flush()
    _notify(db, friend, "invite", f"team-invite:{team.id}:{friend_id}", team=team.name, who=owner.login)
    return item


def accept_invite(db: Session, user: User, team_id: int) -> Team:
    item = db.query(TeamInvite).filter(TeamInvite.team_id == team_id, TeamInvite.user_id == user.id).first()
    team = db.get(Team, team_id)
    if item is None or team is None:
        raise TeamError("Приглашение не найдено")
    if membership(db, user) is not None:
        raise TeamError("Вы уже состоите в команде")
    _add_member(db, team, user)
    return team


def decline_invite(db: Session, user: User, team_id: int) -> None:
    db.query(TeamInvite).filter(TeamInvite.team_id == team_id, TeamInvite.user_id == user.id).delete(
        synchronize_session=False
    )


def join_open(db: Session, user: User, team_id: int) -> Team:
    team = db.get(Team, team_id)
    if team is None or not team.is_open:
        raise TeamError("Эта команда закрыта для вступления")
    if membership(db, user) is not None:
        raise TeamError("Вы уже состоите в команде")
    _add_member(db, team, user)
    return team


def _remove(db: Session, team: Team, user_id: int) -> None:
    db.query(TeamMember).filter(TeamMember.team_id == team.id, TeamMember.user_id == user_id).delete(
        synchronize_session=False
    )
    left = members_of(db, team)
    if not left:
        db.delete(team)
    elif team.owner_id == user_id:
        team.owner_id = left[0].user_id  # the longest-standing member
    db.flush()


def leave(db: Session, user: User) -> None:
    member = membership(db, user)
    if member is None:
        raise TeamError("Вы не состоите в команде")
    _remove(db, db.get(Team, member.team_id), user.id)


def kick(db: Session, owner: User, team: Team, user_id: int) -> None:
    if team.owner_id != owner.id:
        raise TeamError("Исключать может только создатель команды")
    if user_id == owner.id:
        raise TeamError("Себя нельзя исключить: выйдите из команды")
    if db.query(TeamMember.id).filter(TeamMember.team_id == team.id, TeamMember.user_id == user_id).first() is None:
        raise TeamError("Этого человека нет в команде")
    _remove(db, team, user_id)


def open_teams(db: Session, limit: int = 30) -> list[dict]:
    cap = team_size_cap(db)
    rows = (
        db.query(Team, func.count(TeamMember.id))
        .join(TeamMember, TeamMember.team_id == Team.id)
        .filter(Team.is_open.is_(True))
        .group_by(Team.id)
        .having(func.count(TeamMember.id) < cap)
        .order_by(func.count(TeamMember.id).desc(), Team.id)
        .limit(limit)
        .all()
    )
    return [{"id": t.id, "name": t.name, "members": n, "capacity": cap} for t, n in rows]


# --- Progress ---------------------------------------------------------------------


def _counts(db: Session, team: Team, season: Season, metric: str, start: datetime, end: datetime | None) -> dict[int, int]:
    """Events of this kind per member in [start, end), counting only what
    happened after the member joined."""
    query = (
        db.query(PassXpEvent.user_id, func.count(PassXpEvent.id))
        .join(TeamMember, TeamMember.user_id == PassXpEvent.user_id)
        .filter(
            TeamMember.team_id == team.id,
            PassXpEvent.season_id == season.id,
            PassXpEvent.source == metric,
            PassXpEvent.created_at >= start,
            PassXpEvent.created_at >= TeamMember.joined_at,
        )
    )
    if end is not None:
        query = query.filter(PassXpEvent.created_at < end)
    return {uid: n for uid, n in query.group_by(PassXpEvent.user_id)}


def contributions(db: Session, team: Team, season: Season, start: datetime, end: datetime) -> dict[int, int]:
    """XP each member earned for the team's week (study actions only)."""
    rows = (
        db.query(PassXpEvent.user_id, func.coalesce(func.sum(PassXpEvent.amount), 0))
        .join(TeamMember, TeamMember.user_id == PassXpEvent.user_id)
        .filter(
            TeamMember.team_id == team.id,
            PassXpEvent.season_id == season.id,
            PassXpEvent.source.in_(METRICS),
            PassXpEvent.created_at >= start,
            PassXpEvent.created_at < end,
            PassXpEvent.created_at >= TeamMember.joined_at,
        )
        .group_by(PassXpEvent.user_id)
    )
    return {uid: int(total) for uid, total in rows}


def _goal_state(db: Session, team: Team, season: Season, goal: dict, scope: str, start, end, ref: str, claimed: set, member_count: int, lang) -> dict:
    from app.seasonpass.cosmetics import label_for

    target = goal["target_per_member"] * max(2, member_count)
    progress = sum(_counts(db, team, season, goal["metric"], start, end).values())
    reward = goal.get("reward")
    done = progress >= target
    taken = ("team", ref) in claimed
    return {
        "id": goal["id"],
        "scope": scope,
        "metric": goal["metric"],
        "target": target,
        "progress": min(progress, target),
        "xp": goal["xp"],
        "reward": (
            {**reward, "text": label_for(reward, lang) if reward.get("text") else None} if reward else None
        ),
        "claimed": taken,
        "claimable": done and not taken,
    }


def team_state(db: Session, user: User) -> dict:
    """Everything the team screen shows: the person's team (if any) with
    members, contributions and goals, and their pending invitations."""
    from app.core.storage import url_for_key
    from app.seasonpass.cosmetics import badge_keys

    invites = (
        db.query(TeamInvite, Team, User)
        .join(Team, Team.id == TeamInvite.team_id)
        .join(User, User.id == TeamInvite.invited_by)
        .filter(TeamInvite.user_id == user.id)
        .order_by(TeamInvite.id.desc())
        .all()
    )
    out: dict = {
        "team": None,
        "invites": [{"team_id": t.id, "team_name": t.name, "from_login": u.login} for _, t, u in invites],
        "capacity": team_size_cap(db),
    }
    member = membership(db, user)
    if member is None:
        return out
    team = db.get(Team, member.team_id)
    members = members_of(db, team)
    users = {u.id: u for u in db.query(User).filter(User.id.in_([m.user_id for m in members]))}
    badges = badge_keys(db, list(users))
    season = db.query(Season).filter(Season.status == "active").first()

    week = None
    season_goal = None
    shares: dict[int, int] = {}
    if season is not None:
        definition = season_pass(db, season).definition
        now = utc_now()
        monday, wstart, wend = week_bounds(now, season)
        claimed = {
            (k, r)
            for k, r in db.query(PassClaim.kind, PassClaim.ref).filter(
                PassClaim.user_id == user.id, PassClaim.season_id == season.id, PassClaim.kind == "team"
            )
        }
        count = len(members)
        goals = [
            _goal_state(db, team, season, g, "week", wstart, wend, f"week:{monday.isoformat()}:{g['id']}", claimed, count, user.ui_language)
            for g in definition.get("team_goals") or []
        ]
        week = {"starts_on": monday, "ends_at": wend, "goals": goals}
        sg = definition.get("team_season_goal")
        if sg:
            season_goal = _goal_state(
                db, team, season, sg, "season", season.starts_at, season.ends_at, f"season:{sg['id']}", claimed, count, user.ui_language
            )
        shares = contributions(db, team, season, wstart, wend)

    out["team"] = {
        "id": team.id,
        "name": team.name,
        "is_open": team.is_open,
        "is_owner": team.owner_id == user.id,
        "members": [
            {
                "user_id": m.user_id,
                "login": users[m.user_id].login,
                "avatar_url": url_for_key(users[m.user_id].avatar_key),
                "is_owner": m.user_id == team.owner_id,
                "week_xp": shares.get(m.user_id, 0),
                "badge": badges.get(m.user_id),
            }
            for m in members
            if m.user_id in users
        ],
        "week": week,
        "season_goal": season_goal,
    }
    return out


# --- Claiming ------------------------------------------------------------------------


def claim_goal(db: Session, user: User, scope: str, goal_id: str) -> dict:
    """The person takes their share of a finished team goal: bonus XP, and the
    goal's reward when it has one. Once per person and goal."""
    member = membership(db, user)
    if member is None:
        raise TeamError("Вы не состоите в команде")
    team = db.get(Team, member.team_id)
    season = db.query(Season).filter(Season.status == "active").first()
    if season is None:
        raise TeamError("Сейчас нет активного сезона")
    definition = season_pass(db, season).definition
    members = members_of(db, team)
    if scope == "week":
        goal = next((g for g in definition.get("team_goals") or [] if g["id"] == goal_id), None)
        monday, start, end = week_bounds(utc_now(), season)
        ref = f"week:{monday.isoformat()}:{goal_id}"
    elif scope == "season":
        goal = definition.get("team_season_goal")
        goal = goal if goal and goal["id"] == goal_id else None
        start, end = season.starts_at, season.ends_at
        ref = f"season:{goal_id}"
    else:
        raise TeamError("Неизвестная цель")
    if goal is None:
        raise TeamError("Цель не найдена")
    target = goal["target_per_member"] * max(2, len(members))
    if sum(_counts(db, team, season, goal["metric"], start, end).values()) < target:
        raise TeamError("Команда ещё не выполнила цель")
    _record_claim(db, user, season, "team", ref)
    awarded = award_xp(db, user, "team", f"team:{ref}", goal["xp"]) if goal["xp"] else 0
    reward = goal.get("reward")
    if reward:
        _give(db, user, reward, f"Командная цель сезона «{season.name}»", season, ref=f"team:{ref}")
    return {"xp": awarded, "reward": reward}


# --- Notifications -------------------------------------------------------------------

_TEXTS = {
    "invite": {
        "ru": ("Приглашение в команду", "{who} зовёт вас в команду «{team}»."),
        "tg": ("Даъват ба даста", "{who} шуморо ба дастаи «{team}» даъват мекунад."),
        "uz": ("Jamoaga taklif", "{who} sizni «{team}» jamoasiga taklif qilmoqda."),
        "en": ("Team invitation", "{who} invites you to the team “{team}”."),
    },
    "goal": {
        "ru": ("Цель команды выполнена!", "Команда «{team}» выполнила цель. Заберите награду в пропуске сезона."),
        "tg": ("Ҳадафи даста иҷро шуд!", "Дастаи «{team}» ҳадафро иҷро кард. Мукофотро дар гузариши мавсим гиред."),
        "uz": ("Jamoa maqsadi bajarildi!", "«{team}» jamoasi maqsadni bajardi. Mukofotni mavsum o‘tkazmasida oling."),
        "en": ("Team goal reached!", "The team “{team}” reached its goal. Claim your reward in the season pass."),
    },
}


def _notify(db: Session, user: User, kind: str, key: str, **fields) -> None:
    try:
        from app.notifications import send_notification

        lang = user.ui_language if user.ui_language in ("ru", "tg", "uz", "en") else "ru"
        title, body = _TEXTS[kind][lang]
        send_notification(db, user, body.format(**fields), title=title, source="team", dedupe_key=key)
    except Exception:  # a message is a courtesy; never fail the action over it
        pass


def after_xp(db: Session, user: User, season: Season) -> None:
    """Called after a person earned season XP: if that finished a team goal,
    every member is told once. Best effort, never raises."""
    from app.seasonpass.duels import after_xp as duel_after_xp

    duel_after_xp(db, user)
    try:
        member = membership(db, user)
        if member is None:
            return
        team = db.get(Team, member.team_id)
        members = members_of(db, team)
        definition = season_pass(db, season).definition
        monday, wstart, wend = week_bounds(utc_now(), season)
        goals = [("week", g, wstart, wend, f"week:{monday.isoformat()}:{g['id']}") for g in definition.get("team_goals") or []]
        sg = definition.get("team_season_goal")
        if sg:
            goals.append(("season", sg, season.starts_at, season.ends_at, f"season:{sg['id']}"))
        for _scope, g, start, end, ref in goals:
            target = g["target_per_member"] * max(2, len(members))
            if sum(_counts(db, team, season, g["metric"], start, end).values()) >= target:
                users = db.query(User).filter(User.id.in_([m.user_id for m in members])).all()
                for u in users:
                    _notify(db, u, "goal", f"team-goal:{team.id}:{ref}:{u.id}", team=team.name)
    except Exception:
        pass
