"""Admin Web: season pass settings, templates and a season's own copy."""

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin
from app.database import get_db
from app.models.rating import Season
from app.models.season_pass import PassTemplate, SeasonPass
from app.seasonpass.service import (
    PassError,
    apply_template,
    default_definition,
    default_template,
    ensure_monthly_seasons,
    get_pass_settings,
    season_pass,
    validate_definition,
)

router = APIRouter(prefix="/admin/season-pass", tags=["admin-season-pass"])


class SettingsIO(BaseModel):
    xp_word: int = Field(ge=0, le=10000)
    xp_lesson: int = Field(ge=0, le=10000)
    xp_review: int = Field(ge=0, le=10000)
    xp_quest: int = Field(ge=0, le=10000)
    xp_streak: int = Field(ge=0, le=10000)
    xp_daily_goal: int = Field(default=15, ge=0, le=10000)
    xp_comeback: int = Field(default=20, ge=0, le=10000)
    xp_duel_win: int = Field(default=50, ge=0, le=10000)
    duels_enabled: bool = True
    chest_enabled: bool = True
    chest_xp_min: int = Field(default=10, ge=0, le=10000)
    chest_xp_max: int = Field(default=40, ge=0, le=10000)
    chest_freeze_chance: int = Field(default=5, ge=0, le=100)
    freeze_cap: int = Field(default=3, ge=1, le=30)
    team_size: int = Field(default=5, ge=2, le=20)
    auto_monthly_seasons: bool = True
    reminders_enabled: bool = True


class DefinitionIO(BaseModel):
    levels: list[dict]
    tasks: list[dict] = []
    team_goals: list[dict] = []
    team_season_goal: dict | None = None


class TemplateIn(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    definition: DefinitionIO


class TemplateOut(BaseModel):
    id: int
    name: str
    is_default: bool
    definition: DefinitionIO


class SeasonPassOut(BaseModel):
    season_id: int
    season_name: str
    status: str
    template_id: int | None
    definition: DefinitionIO


def _template_out(t: PassTemplate) -> TemplateOut:
    return TemplateOut(id=t.id, name=t.name, is_default=t.is_default, definition=DefinitionIO(**t.definition))


def _valid(definition: DefinitionIO) -> dict:
    try:
        return validate_definition(definition.model_dump())
    except PassError as e:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e)) from None


@router.get("/settings", response_model=SettingsIO)
def get_settings(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    s = get_pass_settings(db)
    db.commit()
    return SettingsIO(
        xp_word=s.xp_word, xp_lesson=s.xp_lesson, xp_review=s.xp_review, xp_quest=s.xp_quest,
        xp_streak=s.xp_streak, xp_daily_goal=s.xp_daily_goal, xp_comeback=s.xp_comeback, xp_duel_win=s.xp_duel_win, duels_enabled=s.duels_enabled,
        chest_enabled=s.chest_enabled, chest_xp_min=s.chest_xp_min, chest_xp_max=s.chest_xp_max,
        chest_freeze_chance=s.chest_freeze_chance, freeze_cap=s.freeze_cap, team_size=s.team_size, auto_monthly_seasons=s.auto_monthly_seasons,
        reminders_enabled=s.reminders_enabled,
    )


@router.put("/settings", response_model=SettingsIO)
def put_settings(payload: SettingsIO, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    s = get_pass_settings(db)
    for field, value in payload.model_dump().items():
        setattr(s, field, value)
    db.commit()
    return payload


@router.get("/templates", response_model=list[TemplateOut])
def list_templates(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    default_template(db)
    db.commit()
    return [_template_out(t) for t in db.query(PassTemplate).order_by(PassTemplate.id)]


@router.get("/default-definition", response_model=DefinitionIO)
def get_default_definition(_admin=Depends(get_current_admin)):
    """A ready-made starting point for a new template."""
    return DefinitionIO(**default_definition())


@router.post("/templates", response_model=TemplateOut, status_code=status.HTTP_201_CREATED)
def create_template(payload: TemplateIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    template = PassTemplate(name=payload.name.strip(), is_default=False, definition=_valid(payload.definition))
    db.add(template)
    db.commit()
    db.refresh(template)
    return _template_out(template)


def _get_template(db: Session, template_id: int) -> PassTemplate:
    template = db.get(PassTemplate, template_id)
    if template is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Шаблон не найден")
    return template


@router.put("/templates/{template_id}", response_model=TemplateOut)
def update_template(
    template_id: int, payload: TemplateIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    template = _get_template(db, template_id)
    template.name = payload.name.strip()
    template.definition = _valid(payload.definition)
    db.commit()
    db.refresh(template)
    return _template_out(template)


@router.post("/templates/{template_id}/copy", response_model=TemplateOut, status_code=status.HTTP_201_CREATED)
def copy_template(template_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    source = _get_template(db, template_id)
    template = PassTemplate(name=f"{source.name} (копия)", is_default=False, definition=source.definition)
    db.add(template)
    db.commit()
    db.refresh(template)
    return _template_out(template)


@router.post("/templates/{template_id}/default", response_model=TemplateOut)
def make_default(template_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    template = _get_template(db, template_id)
    db.query(PassTemplate).update({PassTemplate.is_default: False})
    template.is_default = True
    db.commit()
    db.refresh(template)
    return _template_out(template)


@router.delete("/templates/{template_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_template(template_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    template = _get_template(db, template_id)
    if template.is_default:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Шаблон по умолчанию удалить нельзя")
    db.delete(template)
    db.commit()


def _season(db: Session, season_id: int) -> Season:
    season = db.get(Season, season_id)
    if season is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Сезон не найден")
    return season


def _season_out(sp: SeasonPass, season: Season) -> SeasonPassOut:
    return SeasonPassOut(
        season_id=season.id, season_name=season.name, status=season.status, template_id=sp.template_id,
        definition=DefinitionIO(**sp.definition),
    )


@router.get("/seasons/{season_id}", response_model=SeasonPassOut)
def get_season_pass(season_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    season = _season(db, season_id)
    sp = season_pass(db, season)
    db.commit()
    return _season_out(sp, season)


@router.put("/seasons/{season_id}", response_model=SeasonPassOut)
def put_season_pass(
    season_id: int, payload: DefinitionIO, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    season = _season(db, season_id)
    sp = season_pass(db, season)
    sp.definition = _valid(payload)
    db.commit()
    return _season_out(sp, season)


@router.post("/seasons/{season_id}/apply-template/{template_id}", response_model=SeasonPassOut)
def apply_season_template(
    season_id: int, template_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    season = _season(db, season_id)
    sp = apply_template(db, season, _get_template(db, template_id))
    db.commit()
    return _season_out(sp, season)


class AdminTeamOut(BaseModel):
    id: int
    name: str
    is_open: bool
    members: list[str]


@router.get("/teams", response_model=list[AdminTeamOut])
def list_teams(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Every team with its members' logins (read only)."""
    from app.models.team import Team, TeamMember
    from app.models.user import User

    teams = db.query(Team).order_by(Team.id.desc()).limit(200).all()
    out = []
    for t in teams:
        logins = [
            login
            for (login,) in db.query(User.login)
            .join(TeamMember, TeamMember.user_id == User.id)
            .filter(TeamMember.team_id == t.id)
            .order_by(TeamMember.joined_at)
        ]
        out.append(AdminTeamOut(id=t.id, name=t.name, is_open=t.is_open, members=logins))
    return out


@router.post("/ensure-seasons")
def ensure_seasons(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Creates the missing calendar-month seasons now (also done on its own)."""
    return {"created": ensure_monthly_seasons(db)}


class EconomyOut(BaseModel):
    season_id: int
    season_name: str
    players: int
    total_xp: int
    avg_xp: float
    avg_xp_per_day: float
    xp_by_source: list[dict]
    level_distribution: list[dict]
    claims_by_kind: dict[str, int]
    teams: int
    team_members: int


@router.get("/economy", response_model=EconomyOut | None)
def economy(season_id: int | None = None, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """How the pass is playing out in a season (the live one by default):
    who earns how much, from what, how far people get, what they claim.
    Read-only, from the XP ledger and the claims."""
    from sqlalchemy import func

    from app.core.dates import utc_now
    from app.models.rating import SEASON_ACTIVE
    from app.models.season_pass import PassClaim, PassXpEvent
    from app.models.team import Team, TeamMember
    from app.seasonpass.service import level_for_xp

    q = db.query(Season)
    season = db.get(Season, season_id) if season_id else q.filter(Season.status == SEASON_ACTIVE).first()
    if season is None:
        return None
    levels = season_pass(db, season).definition["levels"]
    per_user = dict(
        db.query(PassXpEvent.user_id, func.sum(PassXpEvent.amount))
        .filter(PassXpEvent.season_id == season.id)
        .group_by(PassXpEvent.user_id)
        .all()
    )
    total = int(sum(per_user.values()))
    players = len(per_user)
    by_level: dict[int, int] = {}
    for xp in per_user.values():
        lvl = level_for_xp(levels, int(xp))[0]
        by_level[lvl] = by_level.get(lvl, 0) + 1
    sources = (
        db.query(PassXpEvent.source, func.sum(PassXpEvent.amount), func.count(PassXpEvent.id))
        .filter(PassXpEvent.season_id == season.id)
        .group_by(PassXpEvent.source)
        .order_by(func.sum(PassXpEvent.amount).desc())
        .all()
    )
    claims = dict(
        db.query(PassClaim.kind, func.count(PassClaim.id)).filter(PassClaim.season_id == season.id).group_by(PassClaim.kind).all()
    )
    end = min(utc_now(), season.ends_at) if season.ends_at else utc_now()
    days = max(1.0, (end - season.starts_at).total_seconds() / 86400)
    return EconomyOut(
        season_id=season.id,
        season_name=season.name,
        players=players,
        total_xp=total,
        avg_xp=round(total / players, 1) if players else 0.0,
        avg_xp_per_day=round(total / players / days, 1) if players else 0.0,
        xp_by_source=[{"source": s, "xp": int(x), "events": int(n)} for s, x, n in sources],
        level_distribution=[{"level": lv, "people": by_level.get(lv, 0)} for lv in range(0, len(levels) + 1)],
        claims_by_kind={k: int(v) for k, v in claims.items()},
        teams=db.query(func.count(Team.id)).scalar() or 0,
        team_members=db.query(func.count(TeamMember.id)).scalar() or 0,
    )


class GrantXpIn(BaseModel):
    user: str = Field(min_length=1, max_length=64)
    amount: int = Field(ge=1, le=1_000_000)


@router.post("/grant-xp")
def grant_xp(payload: GrantXpIn, db: Session = Depends(get_db), admin=Depends(get_current_admin)):
    """Gives one person season XP by hand: their pass level rises at once."""
    import uuid

    from sqlalchemy import func

    from app.models.user import User
    from app.seasonpass.service import award_xp

    key = payload.user.strip()
    query = db.query(User).filter(User.deleted_at.is_(None))
    user = query.filter(User.public_id == int(key)).first() if key.isdigit() else None
    if user is None:
        user = query.filter(func.lower(User.login) == key.lower()).first()
    if user is None:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    given = award_xp(db, user, "admin", f"admin:{admin.id}:{uuid.uuid4().hex}", amount=payload.amount)
    if not given:
        raise HTTPException(status_code=409, detail="Нет идущего сезона")
    db.commit()
    from app.seasonpass.service import user_state

    state = user_state(db, user)
    return {"user_id": user.id, "login": user.login, "amount": given, "level": state["level"] if state else None, "xp": state["xp"] if state else None}


@router.get("/showcase")
def showcase(user: str, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Read-only: what one person wears and owns (frames, badges, titles) and their
    achievements, for the admin showcase page. Changes nothing, tells nobody."""
    from sqlalchemy import func

    from app.core.storage import url_for_key
    from app.models.achievement import Achievement, UserAchievement
    from app.models.season_pass import UserCosmetic
    from app.models.user import User
    from app.seasonpass.cosmetics import collection, label_for, title_key

    key = user.strip()
    query = db.query(User).filter(User.deleted_at.is_(None))
    found = query.filter(User.public_id == int(key)).first() if key.isdigit() else None
    if found is None:
        found = query.filter(func.lower(User.login) == key.lower()).first()
    if found is None:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    coll = collection(db, found)

    def key_of(item_id):
        row = db.get(UserCosmetic, item_id) if item_id else None
        return row.key if row else None

    def title_of(item_id):
        row = db.get(UserCosmetic, item_id) if item_id else None
        return label_for(row, found.ui_language) if row else None

    earned = {
        ua.achievement_id: ua.earned_at
        for ua in db.query(UserAchievement).filter(UserAchievement.user_id == found.id).all()
    }
    achievements = [
        {
            "id": a.id,
            "title": a.title,
            "description": a.description,
            "color": a.color,
            "icon_url": url_for_key(a.icon_key),
            "earned_at": earned[a.id].isoformat() if a.id in earned else None,
        }
        for a in db.query(Achievement).filter(Achievement.enabled.is_(True)).order_by(Achievement.order, Achievement.id).all()
    ]
    return {
        "login": found.login,
        "public_id": found.public_id,
        "avatar_url": url_for_key(found.avatar_key),
        "worn": {
            "frame": key_of(found.equipped_frame_id),
            "badge": key_of(found.equipped_badge_id),
            "title": title_of(found.equipped_title_id),
            "title_key": title_key(db, found),
        },
        "collection": coll,
        "achievements": achievements,
    }
