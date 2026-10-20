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
        xp_streak=s.xp_streak, xp_daily_goal=s.xp_daily_goal, xp_comeback=s.xp_comeback, freeze_cap=s.freeze_cap, team_size=s.team_size, auto_monthly_seasons=s.auto_monthly_seasons,
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
