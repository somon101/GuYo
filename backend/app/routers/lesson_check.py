"""«Проверка слов» before a lesson: one card per lesson word (the original and
four translations, one right), then -- after a right answer -- how easy it
was. Only memory evidence: the answers are recorded (exercise "check") and the
memory model reads them (app/memory/service.py); a word never becomes learned
here, the lesson still decides that.
"""

import random

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session, selectinload

from app.core.content_language import only_translated, primary_translation
from app.core.dates import utc_now
from app.core.deps import get_current_user, require_current_app
from app.core.storage import url_for_key
from app.database import get_db
from app.exercises.common import lesson_words_not_learned
from app.learning.mastery import progress_row
from app.memory.service import CHECK_GRADES
from app.models.learning_settings import LearningSettings
from app.models.lesson import Lesson
from app.models.user import User
from app.models.word import Word
from app.word_attempts import record_word_attempt

router = APIRouter(tags=["lesson-check"])

OPTION_COUNT = 4


class CheckOptionOut(BaseModel):
    word_id: int
    text: str


class CheckItemOut(BaseModel):
    word_id: int
    original: str
    transcription: str | None
    image_url: str | None
    word_audio_url: str | None
    options: list[CheckOptionOut]


class CheckOut(BaseModel):
    enabled: bool
    skip_allowed: bool
    items: list[CheckItemOut]


class CheckAnswerIn(BaseModel):
    word_id: int
    picked_word_id: int | None = None
    # guess / hard / normal / easy -- asked only after a right answer.
    rating: str | None = Field(default=None, pattern="^(guess|hard|normal|easy)$")
    duration_ms: int | None = Field(default=None, ge=0, le=600_000)


class CheckAnswerOut(BaseModel):
    is_correct: bool


def _settings(db: Session) -> tuple[bool, bool]:
    s = db.get(LearningSettings, 1)
    return (s is None or s.check_enabled is not False), (s is None or s.check_skip_allowed is not False)


def _lesson_or_404(db: Session, user: User, lesson_id: int) -> Lesson:
    lesson = db.get(Lesson, lesson_id)
    if lesson is None or lesson.user_id != user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Lesson not found")
    return lesson


def _text(word: Word) -> str | None:
    t = primary_translation(word)
    return t.text if t is not None else None


def _distractors(db: Session, lesson: Lesson, word: Word, taken: set[str], count: int) -> list[Word]:
    """Other words of the dictionary with a translation, whose text differs
    from the right one (and from each other)."""
    pool = (
        db.query(Word)
        .options(selectinload(Word.translations))
        .filter(Word.dictionary_id == lesson.dictionary_id, Word.id != word.id)
        .order_by(func.random())
        .limit(60)
        .all()
    )
    out: list[Word] = []
    for w in only_translated(pool):
        text = _text(w)
        if not text or text in taken:
            continue
        taken.add(text)
        out.append(w)
        if len(out) == count:
            break
    return out


@router.get("/lessons/{lesson_id}/check", response_model=CheckOut)
def get_check(
    lesson_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)
) -> CheckOut:
    enabled, skip_allowed = _settings(db)
    lesson = _lesson_or_404(db, user, lesson_id)
    if not enabled or lesson.check_done_at is not None:
        return CheckOut(enabled=False, skip_allowed=skip_allowed, items=[])

    items: list[CheckItemOut] = []
    for word in only_translated(lesson_words_not_learned(db, lesson)):
        right = _text(word)
        if not right:
            continue
        others = _distractors(db, lesson, word, {right}, OPTION_COUNT - 1)
        if not others:
            continue  # nothing to choose between
        options = [CheckOptionOut(word_id=word.id, text=right)] + [
            CheckOptionOut(word_id=w.id, text=_text(w) or "") for w in others
        ]
        random.shuffle(options)
        items.append(
            CheckItemOut(
                word_id=word.id,
                original=word.word,
                transcription=word.transcription,
                image_url=url_for_key(word.image_key),
                word_audio_url=url_for_key(word.word_audio_key),
                options=options,
            )
        )
    random.shuffle(items)
    return CheckOut(enabled=bool(items), skip_allowed=skip_allowed, items=items)


@router.post("/lessons/{lesson_id}/check/answers", response_model=CheckAnswerOut)
def answer_check(
    lesson_id: int,
    payload: CheckAnswerIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    _app: None = Depends(require_current_app),
) -> CheckAnswerOut:
    lesson = _lesson_or_404(db, user, lesson_id)
    if payload.word_id not in {lw.word_id for lw in lesson.words}:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Word is not in this lesson")
    is_correct = payload.picked_word_id == payload.word_id
    # Only a right answer carries a rating; a missing one counts as "normal".
    rating = (payload.rating or "normal") if is_correct else None
    if rating not in (None, "guess", *CHECK_GRADES):
        rating = "normal"
    progress_row(db, user.id, payload.word_id)
    given = None
    if not is_correct and payload.picked_word_id is not None:
        picked = db.get(Word, payload.picked_word_id)
        given = _text(picked) if picked is not None else None
    record_word_attempt(
        db,
        user_id=user.id,
        word_id=payload.word_id,
        exercise_key="check",
        is_correct=is_correct,
        source="check",
        duration_ms=payload.duration_ms,
        given_answer=given,
        self_rating=rating,
    )
    db.commit()
    return CheckAnswerOut(is_correct=is_correct)


@router.post("/lessons/{lesson_id}/check/finish", status_code=status.HTTP_204_NO_CONTENT)
def finish_check(
    lesson_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)
) -> None:
    """The check is over (finished or skipped): it is not offered again."""
    lesson = _lesson_or_404(db, user, lesson_id)
    lesson.check_done_at = utc_now()
    db.commit()
