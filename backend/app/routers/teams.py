"""Teams: create or join one, invite friends, and take the rewards of the
team's goals. See app/seasonpass/teams.py."""

from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.database import get_db
from app.models.team import Team
from app.models.user import User
from app.seasonpass import teams as svc
from app.seasonpass.service import PassError

router = APIRouter(prefix="/teams", tags=["teams"])


class RewardOut(BaseModel):
    type: str
    amount: int = 1
    key: str | None = None
    text: str | None = None


class GoalOut(BaseModel):
    id: str
    scope: str
    metric: str
    target: int
    progress: int
    xp: int
    reward: RewardOut | None
    claimed: bool
    claimable: bool


class MemberOut(BaseModel):
    user_id: int
    login: str
    avatar_url: str | None
    is_owner: bool
    week_xp: int
    badge: str | None


class WeekOut(BaseModel):
    starts_on: date
    ends_at: datetime
    goals: list[GoalOut]


class TeamOut(BaseModel):
    id: int
    name: str
    is_open: bool
    is_owner: bool
    members: list[MemberOut]
    week: WeekOut | None
    season_goal: GoalOut | None


class InviteOut(BaseModel):
    team_id: int
    team_name: str
    from_login: str


class MyTeamOut(BaseModel):
    team: TeamOut | None
    invites: list[InviteOut]
    capacity: int


class OpenTeamOut(BaseModel):
    id: int
    name: str
    members: int
    capacity: int


class CreateIn(BaseModel):
    name: str
    is_open: bool = False


class UpdateIn(BaseModel):
    name: str | None = None
    is_open: bool | None = None


class InviteIn(BaseModel):
    user_id: int


class ClaimIn(BaseModel):
    scope: str
    goal_id: str


class ClaimOut(BaseModel):
    xp: int
    reward: RewardOut | None
    state: MyTeamOut


def _run(db: Session, user: User, action) -> MyTeamOut:
    """Runs one change, turns a refusal into a 409 and returns the fresh state."""
    try:
        action()
    except PassError as e:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(e)) from None
    db.commit()
    return svc.team_state(db, user)


def _my_team(db: Session, user: User) -> Team:
    member = svc.membership(db, user)
    if member is None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Вы не состоите в команде")
    return db.get(Team, member.team_id)


@router.get("/me", response_model=MyTeamOut)
def get_my_team(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    state = svc.team_state(db, user)
    db.commit()
    return state


@router.get("/open", response_model=list[OpenTeamOut])
def list_open(db: Session = Depends(get_db), _user: User = Depends(get_current_user)):
    return svc.open_teams(db)


@router.post("", response_model=MyTeamOut, status_code=status.HTTP_201_CREATED)
def create(payload: CreateIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _run(db, user, lambda: svc.create_team(db, user, payload.name, payload.is_open))


@router.put("/me", response_model=MyTeamOut)
def update(payload: UpdateIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _run(db, user, lambda: svc.update_team(db, user, _my_team(db, user), payload.name, payload.is_open))


@router.post("/me/invite", response_model=MyTeamOut)
def invite(payload: InviteIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _run(db, user, lambda: svc.invite(db, user, _my_team(db, user), payload.user_id))


@router.post("/invites/{team_id}/accept", response_model=MyTeamOut)
def accept(team_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _run(db, user, lambda: svc.accept_invite(db, user, team_id))


@router.post("/invites/{team_id}/decline", response_model=MyTeamOut)
def decline(team_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _run(db, user, lambda: svc.decline_invite(db, user, team_id))


@router.post("/{team_id}/join", response_model=MyTeamOut)
def join(team_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _run(db, user, lambda: svc.join_open(db, user, team_id))


@router.post("/me/leave", response_model=MyTeamOut)
def leave(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _run(db, user, lambda: svc.leave(db, user))


@router.delete("/me/members/{user_id}", response_model=MyTeamOut)
def kick(user_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _run(db, user, lambda: svc.kick(db, user, _my_team(db, user), user_id))


@router.post("/goals/claim", response_model=ClaimOut)
def claim(payload: ClaimIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    result: dict = {}

    def action():
        result.update(svc.claim_goal(db, user, payload.scope, payload.goal_id))

    state = _run(db, user, action)
    return ClaimOut(xp=result.get("xp", 0), reward=result.get("reward"), state=state)
