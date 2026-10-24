"""The daily goal: how many words a person wants to practise each day."""

from datetime import datetime

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.dates import DUSHANBE_TZ, dushanbe_today
from app.core.deps import get_current_user
from app.database import get_db
from app.memory.service import CHECK_KEY
from app.models.user import User
from app.models.word_attempt import WordAttempt
from app.chests import rewards
from app.models.chests import DailyGoalClaim

router = APIRouter(prefix="/daily-goal", tags=["daily-goal"])


class RewardOut(BaseModel):
    type: str
    amount: int
    key: str | None = None


class TierOut(BaseModel):
    words: int
    rewards: list[RewardOut]
    claimed: bool


class DailyGoalOut(BaseModel):
    goal: int
    done: int
    completed: bool
    # True only on the call that finished the goal: the app celebrates then.
    just_completed: bool = False
    xp: int = 0
    chests: list[str] = []
    diamonds: int = 0
    points: int = 0
    options: list[int] = []
    tiers: list[TierOut] = []


class DailyGoalIn(BaseModel):
    goal: int = Field(ge=1, le=1000)


def words_today(db: Session, user_id: int) -> int:
    """Different words practised since midnight (Dushanbe)."""
    start = datetime.combine(dushanbe_today(), datetime.min.time(), tzinfo=DUSHANBE_TZ)
    return (
        db.query(func.count(func.distinct(WordAttempt.word_id)))
        .filter(WordAttempt.user_id == user_id, WordAttempt.created_at >= start, WordAttempt.exercise_key != CHECK_KEY)
        .scalar()
        or 0
    )


def state(db: Session, user: User) -> DailyGoalOut:
    done = words_today(db, user.id)
    today = dushanbe_today()
    tiers = rewards.daily_tiers(db)
    options = [t["words"] for t in tiers]
    if user.daily_goal not in options:
        user.daily_goal = min(options, key=lambda g: abs(g - user.daily_goal))
    completed = done >= user.daily_goal
    # Once per day per tier: the claim row is unique on (user, day, tier).
    given = rewards.claim_daily_goal(db, user, done, today) if completed else None
    claimed = {c.words for c in db.query(DailyGoalClaim).filter_by(user_id=user.id, day=today)}
    return DailyGoalOut(
        goal=user.daily_goal, done=done, completed=completed, just_completed=given is not None,
        xp=given["xp"] if given else 0, chests=given["chests"] if given else [],
        diamonds=given["diamonds"] if given else 0, points=given["points"] if given else 0,
        options=options,
        tiers=[TierOut(words=t["words"], rewards=t["rewards"], claimed=t["words"] in claimed) for t in tiers],
    )


@router.get("", response_model=DailyGoalOut)
def get_goal(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    out = state(db, user)
    db.commit()
    return out


@router.put("", response_model=DailyGoalOut)
def set_goal(payload: DailyGoalIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    options = [t["words"] for t in rewards.daily_tiers(db)]
    if payload.goal not in options:
        payload.goal = min(options, key=lambda g: abs(g - payload.goal))
    user.daily_goal = payload.goal
    out = state(db, user)
    db.commit()
    return out
