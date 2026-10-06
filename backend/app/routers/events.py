"""POST /events: the app reports history steps only it can see (a lesson
opened or left, a quest opened, the app opened) -- app/analytics/history.py."""

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.analytics.history import CLIENT_KINDS, log_event
from app.core.deps import get_current_user
from app.database import get_db
from app.models.lesson import Lesson
from app.models.quest import Quest
from app.models.user import User

router = APIRouter(tags=["events"])


class EventIn(BaseModel):
    kind: str = Field(max_length=32)
    lesson_id: int | None = None
    quest_id: int | None = None
    data: dict | None = None


@router.post("/events", status_code=status.HTTP_204_NO_CONTENT)
def record_event(payload: EventIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    if payload.kind not in CLIENT_KINDS:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Unknown event kind")
    lesson_id = payload.lesson_id
    if lesson_id is not None:
        lesson = db.get(Lesson, lesson_id)
        if lesson is None or lesson.user_id != user.id:
            lesson_id = None
    quest_id = payload.quest_id if payload.quest_id is not None and db.get(Quest, payload.quest_id) else None
    # Small, flat facts only (exercise reached, screen...): never a dump.
    data = {
        k: v
        for k, v in (payload.data or {}).items()
        if isinstance(v, (str, int, float, bool)) and len(str(v)) <= 100
    }
    log_event(
        db, user.id, payload.kind, lesson_id=lesson_id, quest_id=quest_id, data=dict(list(data.items())[:10]) or None
    )
    db.commit()
