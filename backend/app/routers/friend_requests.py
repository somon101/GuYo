"""Friend requests: ask, take back, accept, decline. See app/social/friends.py."""

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.database import get_db
from app.models.user import User
from app.social import friends as svc

router = APIRouter(prefix="/friends/requests", tags=["friends"])


class PersonOut(BaseModel):
    user_id: int
    public_id: int | None = None
    login: str
    avatar_url: str | None = None


class RequestsOut(BaseModel):
    incoming: list[PersonOut]
    outgoing: list[PersonOut]


class AskIn(BaseModel):
    user_id: int


class RelationOut(BaseModel):
    user_id: int
    relation: str  # self | friend | sent | received | none


def _run(db: Session, user: User, other_id: int, action) -> RelationOut:
    try:
        action()
    except svc.FriendError as e:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(e)) from None
    db.commit()
    return RelationOut(user_id=other_id, relation=svc.relation(db, user.id, other_id))


@router.get("", response_model=RequestsOut)
def my_requests(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return svc.requests_state(db, user)


@router.post("", response_model=RelationOut)
def ask(payload: AskIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """«Добавить в друзья»: sends a request (or, when they already asked you, makes you friends)."""
    return _run(db, user, payload.user_id, lambda: svc.send_request(db, user, payload.user_id))


@router.delete("/{user_id}", response_model=RelationOut)
def take_back(user_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _run(db, user, user_id, lambda: svc.cancel_request(db, user, user_id))


@router.post("/{user_id}/accept", response_model=RelationOut)
def accept(user_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _run(db, user, user_id, lambda: svc.accept(db, user, user_id))


@router.post("/{user_id}/decline", response_model=RelationOut)
def decline(user_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _run(db, user, user_id, lambda: svc.decline(db, user, user_id))
