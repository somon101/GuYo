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
from app.seasonpass import award_xp

router = APIRouter(prefix="/daily-goal", tags=["daily-goal"])

GOALS = (5, 10, 20)


class DailyGoalOut(BaseModel):
    goal: int
    done: int
    completed: bool
    # True only on the call that finished the goal: the app celebrates then.
    just_completed: bool = False
    xp: int = 0
    options: list[int] = list(GOALS)


class DailyGoalIn(BaseModel):
    goal: int = Field(ge=GOALS[0], le=GOALS[-1])


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
    completed = done >= user.daily_goal
    xp = 0
    if completed:
        # Once per day: award_xp ignores a second award for the same key.
        xp = award_xp(db, user, "daily_goal", f"daily_goal:{dushanbe_today().isoformat()}")
    return DailyGoalOut(goal=user.daily_goal, done=done, completed=completed, just_completed=xp > 0, xp=xp)


@router.get("", response_model=DailyGoalOut)
def get_goal(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    out = state(db, user)
    db.commit()
    return out


@router.put("", response_model=DailyGoalOut)
def set_goal(payload: DailyGoalIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    if payload.goal not in GOALS:
        payload.goal = min(GOALS, key=lambda g: abs(g - payload.goal))
    user.daily_goal = payload.goal
    out = state(db, user)
    db.commit()
    return out
