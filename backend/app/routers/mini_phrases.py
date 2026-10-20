"""The learner's side of mini-phrases: answering "Собери фразу" (checked here
against the stored parts, rating points once per mini-phrase) and the open
mini-phrases listed in Практика."""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.achievements import check_and_grant_achievements
from app.core.deps import get_current_user
from app.database import get_db
from app.mini_phrases import award_points_once, check_answer, mark_done, mini_phrase_out
from app.models.lesson import Lesson
from app.models.mini_phrase import LessonMiniPhrase, MiniPhrase, UserMiniPhraseDone
from app.models.user import User
from app.schemas.mini_phrase import MiniPhraseAnswerIn, MiniPhraseAnswerOut, MiniPhraseOut

router = APIRouter(tags=["mini-phrases"])


@router.get("/dictionaries/{dictionary_id}/mini-phrases/open", response_model=list[MiniPhraseOut])
def list_open_mini_phrases(dictionary_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Практика: every mini-phrase this user has already gone through in a
    lesson, newest first -- только записи языка, который человек изучает."""
    from app.core.content_language import learning_language
    from app.models.dictionary import Dictionary

    dictionary = db.get(Dictionary, dictionary_id)
    target = learning_language() or ((dictionary.language if dictionary is not None else None) or "ru")
    rows = (
        db.query(MiniPhrase)
        .join(UserMiniPhraseDone, UserMiniPhraseDone.mini_phrase_id == MiniPhrase.id)
        .filter(
            UserMiniPhraseDone.user_id == user.id,
            MiniPhrase.dictionary_id == dictionary_id,
            MiniPhrase.enabled.is_(True),
            (MiniPhrase.language == target) | (MiniPhrase.language.is_(None)),
        )
        .order_by(UserMiniPhraseDone.created_at.desc(), MiniPhrase.id.desc())
        .all()
    )
    return [mini_phrase_out(db, user, mp) for mp in rows]


@router.post("/mini-phrases/{mini_phrase_id}/answer", response_model=MiniPhraseAnswerOut)
def answer_mini_phrase(
    mini_phrase_id: int,
    payload: MiniPhraseAnswerIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    mp = db.get(MiniPhrase, mini_phrase_id)
    if mp is None or not mp.enabled:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mini-phrase not found")

    in_lesson = False
    if payload.lesson_id is not None:
        in_lesson = (
            db.query(LessonMiniPhrase.id)
            .join(Lesson, Lesson.id == LessonMiniPhrase.lesson_id)
            .filter(
                LessonMiniPhrase.lesson_id == payload.lesson_id,
                LessonMiniPhrase.mini_phrase_id == mp.id,
                Lesson.user_id == user.id,
            )
            .first()
            is not None
        )
    is_open = (
        db.query(UserMiniPhraseDone.id)
        .filter(UserMiniPhraseDone.user_id == user.id, UserMiniPhraseDone.mini_phrase_id == mp.id)
        .first()
        is not None
    )
    # Only a mini-phrase this user was actually given (in their lesson, or
    # already open in Практика) can be answered.
    if not in_lesson and not is_open:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mini-phrase not found")

    correct = check_answer(mp, payload.answer)
    points = 0
    if correct:
        points = award_points_once(db, user, mp.id)
    if in_lesson:
        mark_done(db, user.id, mp.id)
        db.flush()
        check_and_grant_achievements(db, user, "mini_phrases_done")
    db.commit()
    return MiniPhraseAnswerOut(correct=correct, points_awarded=points, correct_text=mp.text)
