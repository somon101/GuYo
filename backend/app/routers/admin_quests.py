"""Admin Web's Quest CRUD. `exercise_key` is validated against the SAME
EXERCISE_TYPES registry Lessons use (app/exercises/__init__.py) -- never a
free-text field, and never a second exercise-type catalog."""

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin
from app.database import get_db
from app.exercises import EXERCISE_TYPES
from app.models.quest import Quest, UserQuestWordDay
from app.models.word_level import WordLevel
from app.schemas.quest import QuestOut, ReorderQuestsIn

router = APIRouter(prefix="/admin/quests", tags=["admin-quests"])


class QuestCreateIn(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    word_level_id: int
    exercise_key: str
    reward_points: int = Field(ge=0)
    # How many successful attempts count as "done for today" -- the goal a
    # user's progress bar fills toward. Never a second reward rule: every
    # success still grants reward_points, target reached or not.
    daily_target: int = Field(default=1, ge=1)
    enabled: bool = True
    order: int = 0


class QuestUpdateIn(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=255)
    word_level_id: int | None = None
    exercise_key: str | None = None
    reward_points: int | None = Field(default=None, ge=0)
    daily_target: int | None = Field(default=None, ge=1)
    enabled: bool | None = None
    order: int | None = None


def _out(quest: Quest, level_name: str) -> QuestOut:
    return QuestOut(
        id=quest.id, name=quest.name, word_level_id=quest.word_level_id, word_level_name=level_name,
        exercise_key=quest.exercise_key, reward_points=quest.reward_points, daily_target=quest.daily_target,
        enabled=quest.enabled, order=quest.order,
    )


def _level_name(db: Session, word_level_id: int) -> str:
    level = db.get(WordLevel, word_level_id)
    return level.name if level else "?"


def _validate_exercise_key(exercise_key: str) -> None:
    if exercise_key not in EXERCISE_TYPES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Unknown exercise_key '{exercise_key}' -- must be one of {sorted(EXERCISE_TYPES)}",
        )


def _validate_word_level(db: Session, word_level_id: int) -> None:
    if db.get(WordLevel, word_level_id) is None:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Unknown word_level_id")


@router.get("", response_model=list[QuestOut])
def list_quests(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    # Personal quests (Quest.owner_user_id set -- see
    # app/priority/quests_auto.py) never appear in this admin CRUD list:
    # they have no word_level_id of their own and aren't something an
    # admin authored or should edit/delete here.
    quests = db.query(Quest).filter(Quest.owner_user_id.is_(None)).order_by(Quest.order, Quest.id).all()
    return [_out(q, _level_name(db, q.word_level_id)) for q in quests]


@router.get("/exercise-types", response_model=list[str])
def list_quest_exercise_types(_admin=Depends(get_current_admin)):
    """The only exercise_key values a Quest may target -- the same 5
    word-scoped types Lessons already use, never the 2 Practice-only ones
    (Собери фразу / Собери фразу на слух), which aren't wired to a
    specific word_id on the backend."""
    return sorted(EXERCISE_TYPES)


@router.post("", response_model=QuestOut, status_code=status.HTTP_201_CREATED)
def create_quest(payload: QuestCreateIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    _validate_exercise_key(payload.exercise_key)
    _validate_word_level(db, payload.word_level_id)

    quest = Quest(
        name=payload.name.strip(), word_level_id=payload.word_level_id, exercise_key=payload.exercise_key,
        reward_points=payload.reward_points, daily_target=payload.daily_target, enabled=payload.enabled,
        order=payload.order,
    )
    db.add(quest)
    db.commit()
    db.refresh(quest)
    return _out(quest, _level_name(db, quest.word_level_id))


def _get_quest_or_404(db: Session, quest_id: int) -> Quest:
    # Excludes personal quests same as list_quests above -- an admin can
    # never edit/delete one by id either, even by guessing it.
    quest = db.query(Quest).filter(Quest.id == quest_id, Quest.owner_user_id.is_(None)).first()
    if quest is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Quest not found")
    return quest


@router.patch("/{quest_id}", response_model=QuestOut)
def update_quest(quest_id: int, payload: QuestUpdateIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    quest = _get_quest_or_404(db, quest_id)

    if payload.exercise_key is not None:
        _validate_exercise_key(payload.exercise_key)
        quest.exercise_key = payload.exercise_key
    if payload.word_level_id is not None:
        _validate_word_level(db, payload.word_level_id)
        quest.word_level_id = payload.word_level_id
    if payload.name is not None:
        quest.name = payload.name.strip()
    if payload.reward_points is not None:
        quest.reward_points = payload.reward_points
    if payload.daily_target is not None:
        quest.daily_target = payload.daily_target
    if payload.enabled is not None:
        quest.enabled = payload.enabled
    if payload.order is not None:
        quest.order = payload.order

    db.commit()
    db.refresh(quest)
    return _out(quest, _level_name(db, quest.word_level_id))


@router.put("/order", response_model=list[QuestOut])
def reorder_quests(payload: ReorderQuestsIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    quests = db.query(Quest).filter(Quest.id.in_(payload.quest_ids), Quest.owner_user_id.is_(None)).all()
    by_id = {q.id: q for q in quests}
    missing = [i for i in payload.quest_ids if i not in by_id]
    if missing:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Unknown quest ids: {missing}")

    for position, quest_id in enumerate(payload.quest_ids):
        by_id[quest_id].order = position
    db.commit()

    ordered = db.query(Quest).filter(Quest.owner_user_id.is_(None)).order_by(Quest.order, Quest.id).all()
    return [_out(q, _level_name(db, q.word_level_id)) for q in ordered]


@router.delete("/{quest_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_quest(quest_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Refuses to delete a quest any UserQuestWordDay row still references
    (i.e. it's already been completed by at least one user) -- disable it
    instead, same "history is never silently erased" rule as Achievement/
    Rank deletion."""
    quest = _get_quest_or_404(db, quest_id)
    referenced = db.query(UserQuestWordDay).filter(UserQuestWordDay.quest_id == quest_id).first() is not None
    if referenced:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Этот квест уже выполнялся пользователями -- отключите его вместо удаления",
        )
    db.delete(quest)
    db.commit()
