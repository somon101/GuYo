"""Изучение слов ("Learning Words"): a per-user, per-language queue of
existing Word rows the user hasn't learned yet.

Nothing here duplicates Word, Category or Dictionary -- a session only ever
stores word_id references (see app/models/learning.py), and the card shown
to the user is produced by the exact same `word_to_out` the dictionary/
editor already use. The backend is the sole source of truth: random
selection, queue order and completion are all decided and persisted here,
never recomputed or trusted from the client.
"""
from sqlalchemy import func
from sqlalchemy.orm import Session
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.deps import get_current_user
from app.database import get_db
from app.models.category import Category
from app.models.dictionary import Dictionary
from app.models.learning import LearnedWord, LearningSession, LearningSessionItem
from app.models.user import User
from app.models.word import Word
from app.routers.words import word_to_out
from app.schemas.learning import CreateLearningSessionIn, LearnedCategoryOut, LearningSessionOut
from app.schemas.word import WordOut

router = APIRouter(tags=["learning"])


def _get_published_dictionary_or_404(db: Session, dictionary_id: int) -> Dictionary:
    dictionary = db.get(Dictionary, dictionary_id)
    if dictionary is None or not dictionary.is_published:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")
    return dictionary


def _get_active_session(db: Session, user_id: int, dictionary_id: int) -> LearningSession | None:
    return (
        db.query(LearningSession)
        .filter(
            LearningSession.user_id == user_id,
            LearningSession.dictionary_id == dictionary_id,
            LearningSession.is_completed.is_(False),
        )
        .first()
    )


def _touch_completion(db: Session, session: LearningSession) -> None:
    """Self-heals `is_completed` from the actual item states -- covers the
    case where every remaining item's Word got deleted from the dictionary
    (cascade removes the item rows too), which would otherwise leave a
    session with nothing left to show but no explicit completion."""
    if session.is_completed:
        return
    remaining = (
        db.query(func.count(LearningSessionItem.id))
        .filter(LearningSessionItem.session_id == session.id, LearningSessionItem.status != "learned")
        .scalar()
    )
    if remaining == 0:
        session.is_completed = True
        session.completed_at = func.now()


def _get_owned_session_or_404(db: Session, user_id: int, session_id: int) -> LearningSession:
    session = db.get(LearningSession, session_id)
    if session is None or session.user_id != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Learning session not found")
    return session


def _get_session_item_or_404(db: Session, session_id: int, word_id: int) -> LearningSessionItem:
    item = (
        db.query(LearningSessionItem)
        .filter(LearningSessionItem.session_id == session_id, LearningSessionItem.word_id == word_id)
        .first()
    )
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Word not in this session")
    return item


def _session_to_out(db: Session, session: LearningSession) -> LearningSessionOut:
    total = db.query(func.count(LearningSessionItem.id)).filter(
        LearningSessionItem.session_id == session.id
    ).scalar()
    remaining = db.query(func.count(LearningSessionItem.id)).filter(
        LearningSessionItem.session_id == session.id, LearningSessionItem.status != "learned"
    ).scalar()
    learned = total - remaining

    current_item = (
        db.query(LearningSessionItem)
        .filter(LearningSessionItem.session_id == session.id, LearningSessionItem.status != "learned")
        .order_by(LearningSessionItem.position.asc())
        .first()
    )
    current_word = word_to_out(current_item.word) if current_item is not None else None

    return LearningSessionOut(
        id=session.id,
        dictionary_id=session.dictionary_id,
        total_count=total,
        remaining_count=remaining,
        learned_count=learned,
        is_completed=session.is_completed,
        current_word=current_word,
    )


@router.get("/learning/sessions/active", response_model=LearningSessionOut)
def get_active_learning_session(
    dictionary_id: int = Query(...),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    _get_published_dictionary_or_404(db, dictionary_id)
    session = _get_active_session(db, user.id, dictionary_id)
    if session is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No active learning session")
    _touch_completion(db, session)
    if session.is_completed:
        db.commit()
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No active learning session")
    db.commit()
    return _session_to_out(db, session)


@router.post(
    "/learning/sessions", response_model=LearningSessionOut, status_code=status.HTTP_201_CREATED
)
def create_learning_session(
    payload: CreateLearningSessionIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Random selection happens exactly once, right here: pick `count`
    word_ids from this dictionary that the user hasn't learned yet, and
    freeze them into LearningSessionItem rows. Nothing after this point
    ever re-rolls or adds to that set."""
    dictionary = _get_published_dictionary_or_404(db, payload.dictionary_id)

    if _get_active_session(db, user.id, dictionary.id) is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An active learning session already exists for this language",
        )

    learned_word_ids = db.query(LearnedWord.word_id).filter(LearnedWord.user_id == user.id).subquery()
    available_count = (
        db.query(func.count(Word.id))
        .filter(Word.dictionary_id == dictionary.id, ~Word.id.in_(learned_word_ids))
        .scalar()
    )
    if available_count == 0:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Все доступные слова уже изучены")

    candidate_ids = [
        row[0]
        for row in db.query(Word.id)
        .filter(Word.dictionary_id == dictionary.id, ~Word.id.in_(learned_word_ids))
        .order_by(func.random())
        .limit(payload.count)
        .all()
    ]

    session = LearningSession(user_id=user.id, dictionary_id=dictionary.id)
    db.add(session)
    db.flush()  # assign session.id for the items below

    for position, word_id in enumerate(candidate_ids, start=1):
        db.add(LearningSessionItem(session_id=session.id, word_id=word_id, status="new", position=position))

    db.commit()
    db.refresh(session)
    return _session_to_out(db, session)


@router.post("/learning/sessions/{session_id}/words/{word_id}/learned", response_model=LearningSessionOut)
def mark_word_learned(
    session_id: int,
    word_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Idempotent: calling this again for a word already marked learned in
    this session just returns the current state as-is -- even if the
    session has since completed -- never a second learned_words row (the
    unique constraint backs this up regardless) and never a spurious error
    for what is just a harmless repeat (double tap, retried request)."""
    session = _get_owned_session_or_404(db, user.id, session_id)
    item = _get_session_item_or_404(db, session.id, word_id)

    if item.status == "learned":
        return _session_to_out(db, session)

    if session.is_completed:
        # The session finished by some other path (e.g. another device)
        # before this word was ever marked -- a genuine desync, not a
        # simple repeat.
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Learning session already completed")

    item.status = "learned"
    db.flush()  # this session's autoflush is off -- _touch_completion must see this update
    already_learned = (
        db.query(LearnedWord).filter(LearnedWord.user_id == user.id, LearnedWord.word_id == word_id).first()
    )
    if already_learned is None:
        db.add(LearnedWord(user_id=user.id, word_id=word_id))

    _touch_completion(db, session)
    db.commit()
    db.refresh(session)
    return _session_to_out(db, session)


@router.post("/learning/sessions/{session_id}/words/{word_id}/review", response_model=LearningSessionOut)
def mark_word_for_review(
    session_id: int,
    word_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Sends the word to the back of the session's own queue -- never adds
    a new word, never removes this one from the fixed set. It naturally
    reappears once every other currently-outstanding item has had its
    turn, which is what reproduces the "repeat cycle" behavior without
    tracking explicit round boundaries."""
    session = _get_owned_session_or_404(db, user.id, session_id)
    item = _get_session_item_or_404(db, session.id, word_id)

    if item.status == "learned":
        # Already learned (can't be un-learned via review) -- harmless
        # no-op, same reasoning as the idempotent /learned endpoint.
        return _session_to_out(db, session)

    if session.is_completed:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Learning session already completed")

    max_position = (
        db.query(func.max(LearningSessionItem.position))
        .filter(LearningSessionItem.session_id == session.id)
        .scalar()
        or 0
    )
    item.status = "review"
    item.position = max_position + 1

    db.commit()
    db.refresh(session)
    return _session_to_out(db, session)


@router.get("/learned-words/categories", response_model=list[LearnedCategoryOut])
def list_learned_word_categories(
    dictionary_id: int = Query(...),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Only categories the user has at least one learned word in -- a
    category with zero learned words simply never appears, and a brand new
    one shows up the moment its first word is learned, since this is a
    live count, not a stored list."""
    _get_published_dictionary_or_404(db, dictionary_id)
    rows = (
        db.query(Word.category_id, Category.name, func.count(LearnedWord.id))
        .join(LearnedWord, LearnedWord.word_id == Word.id)
        .outerjoin(Category, Category.id == Word.category_id)
        .filter(LearnedWord.user_id == user.id, Word.dictionary_id == dictionary_id)
        .group_by(Word.category_id, Category.name)
        .order_by(Category.name)
        .all()
    )
    return [
        LearnedCategoryOut(category_id=category_id, category_name=name or "Без категории", learned_count=count)
        for category_id, name, count in rows
    ]


@router.get("/learned-words", response_model=list[WordOut])
def list_learned_words(
    dictionary_id: int = Query(...),
    category_id: int | None = Query(None),
    uncategorized: bool = Query(False),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    _get_published_dictionary_or_404(db, dictionary_id)
    query = (
        db.query(Word)
        .join(LearnedWord, LearnedWord.word_id == Word.id)
        .filter(LearnedWord.user_id == user.id, Word.dictionary_id == dictionary_id)
    )
    if uncategorized:
        query = query.filter(Word.category_id.is_(None))
    elif category_id is not None:
        query = query.filter(Word.category_id == category_id)

    words = query.order_by(Word.id).all()
    return [word_to_out(w) for w in words]
