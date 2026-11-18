"""The «Лента»: see app/social/feed.py."""

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.database import get_db
from app.models.user import User
from app.social import feed as svc

router = APIRouter(prefix="/feed", tags=["feed"])


class CommentIn(BaseModel):
    phrase: str


class SettingsIn(BaseModel):
    friends_only: bool


def _run(db: Session, action):
    try:
        result = action()
    except svc.FeedError as e:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e)) from None
    db.commit()
    return result


@router.get("")
def get_feed(offset: int = 0, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    data = svc.feed(db, user, max(0, offset))
    if offset == 0:
        data["suggestions"] = svc.suggestions(db, user)
        data["friends_only"] = user.feed_friends_only
    db.commit()
    return data


@router.get("/suggestions")
def suggestions(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return svc.suggestions(db, user)


@router.put("/settings")
def settings(payload: SettingsIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    user.feed_friends_only = payload.friends_only
    db.commit()
    return {"friends_only": user.feed_friends_only}


@router.post("/{card_id}/like")
def like(card_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _run(db, lambda: svc.set_like(db, user, card_id, True))


@router.delete("/{card_id}/like")
def unlike(card_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _run(db, lambda: svc.set_like(db, user, card_id, False))


@router.get("/{card_id}/likers")
def likers(card_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _run(db, lambda: svc.likers(db, user, card_id))


@router.post("/{card_id}/comment")
def comment(card_id: int, payload: CommentIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _run(db, lambda: svc.set_comment(db, user, card_id, payload.phrase))


@router.delete("/{card_id}/comment")
def uncomment(card_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _run(db, lambda: svc.set_comment(db, user, card_id, None))


@router.post("/{card_id}/hide", status_code=status.HTTP_204_NO_CONTENT)
def hide(card_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    _run(db, lambda: svc.hide(db, user, card_id))
