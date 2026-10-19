"""Admin Web's view of the memory model while it runs in the shadow: how
much of the history is modelled, and how well it predicts real answers
compared with today's Priority (app/memory/evaluation.py)."""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin
from app.database import get_db
from app.memory.evaluation import evaluate
from app.memory.service import memory_coverage

router = APIRouter(prefix="/admin/memory", tags=["admin-memory"])


@router.get("/evaluation")
def get_memory_evaluation(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    modelled, total = memory_coverage(db)
    return {"modelled_pairs": modelled, "pairs_with_answers": total, **evaluate(db)}


# --- Аналитика → «Память»: why a word is in «Повторить сегодня» -----------

from datetime import datetime  # noqa: E402

from fastapi import HTTPException, Query, status  # noqa: E402

from app.core.dates import utc_now  # noqa: E402
from app.memory.service import (  # noqa: E402
    explain_days,
    falls_below_at,
    recall_curve,
    recall_probability,
)
from app.models.lesson import Lesson  # noqa: E402
from app.models.mini_phrase import MiniPhrase  # noqa: E402
from app.models.phrase import Phrase  # noqa: E402
from app.models.review_list import STATUS_CLOSED, ReviewList, ReviewListWord  # noqa: E402
from app.models.user import User  # noqa: E402
from app.models.word import Word  # noqa: E402
from app.models.word_attempt import WordAttempt  # noqa: E402
from app.models.word_progress import WordProgress  # noqa: E402

CLOSED_LISTS_SHOWN = 10


def _user_or_404(db: Session, user_id: int) -> User:
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return user


def _translation(word: Word) -> str | None:
    return word.translations[0].text if word.translations else None


def _settings(db: Session) -> dict:
    from app.exercises.common import get_threshold
    from app.memory.review_lists import MAX_OPEN_LISTS, list_size
    from app.priority.settings import get_priority_settings

    s = get_priority_settings(db)
    return {
        "memory_enabled": s.memory_enabled,
        "target": s.memory_target_retention,
        "learned_threshold": get_threshold(db),
        "list_size": list_size(db),
        "max_open_lists": MAX_OPEN_LISTS,
    }


def _list_out(db: Session, rl: ReviewList, now: datetime) -> dict:
    rows = (
        db.query(ReviewListWord, Word, WordProgress)
        .join(Word, Word.id == ReviewListWord.word_id)
        .outerjoin(
            WordProgress,
            (WordProgress.word_id == ReviewListWord.word_id) & (WordProgress.user_id == rl.user_id),
        )
        .filter(ReviewListWord.list_id == rl.id)
        .order_by(ReviewListWord.position)
        .all()
    )
    words = []
    for entry, word, progress in rows:
        words.append(
            {
                "word_id": word.id,
                "word": word.word,
                "translation": _translation(word),
                "position": entry.position,
                "recall_at_entry": entry.recall,
                "recall_now": recall_probability(progress, now) if progress is not None else None,
                "target": entry.target,
                "done_at": entry.done_at,
            }
        )
    return {
        "id": rl.id,
        "status": rl.status,
        "size": rl.size,
        "created_at": rl.created_at,
        "activated_at": rl.activated_at,
        "closed_at": rl.closed_at,
        "notified_at": rl.notified_at,
        "done": sum(1 for w in words if w["done_at"] is not None),
        "words": words,
    }


@router.get("/users/{user_id}/lists")
def get_user_review_lists(
    user_id: int,
    dictionary_id: int = Query(...),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """The user's «Повторить сегодня»: the active list, the queue, and the
    last closed lists -- each word with its recall when the list was made
    and now."""
    _user_or_404(db, user_id)
    now = utc_now()
    base = db.query(ReviewList).filter(ReviewList.user_id == user_id, ReviewList.dictionary_id == dictionary_id)
    open_lists = base.filter(ReviewList.status != STATUS_CLOSED).order_by(ReviewList.id).all()
    closed = base.filter(ReviewList.status == STATUS_CLOSED).order_by(ReviewList.id.desc()).limit(CLOSED_LISTS_SHOWN).all()
    return {
        "settings": _settings(db),
        "open": [_list_out(db, rl, now) for rl in open_lists],
        "closed": [_list_out(db, rl, now) for rl in closed],
    }


def _attempt_out(a: WordAttempt, lessons: dict, phrases: dict, minis: dict) -> dict:
    lesson = lessons.get(a.lesson_id)
    return {
        "id": a.id,
        "created_at": a.created_at,
        "exercise_key": a.exercise_key,
        "is_correct": a.is_correct,
        "timed_out": a.timed_out,
        "given_answer": a.given_answer,
        "duration_ms": a.duration_ms,
        "score_after": a.score_after,
        "source": "review" if a.review_list_id is not None else a.source,
        "review_list_id": a.review_list_id,
        "lesson_id": a.lesson_id,
        "lesson_number": lesson.number if lesson is not None else None,
        "phrase": phrases.get(a.phrase_id),
        "mini_phrase": minis.get(a.mini_phrase_id),
    }


@router.get("/users/{user_id}/words/{word_id}")
def get_memory_word(
    user_id: int,
    word_id: int,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """The full «Память» card for one (user, word): the model's state now,
    every list the word was put in and why, the day-by-day history that
    produced the state (grade and its reason, recall before the day,
    stability after), every answer with its lesson/phrase/exercise, the
    errors, and the forgetting curve."""
    user = _user_or_404(db, user_id)
    word = db.get(Word, word_id)
    if word is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Word not found")
    settings = _settings(db)
    now = utc_now()
    progress = (
        db.query(WordProgress).filter(WordProgress.user_id == user_id, WordProgress.word_id == word_id).first()
    )
    attempts = (
        db.query(WordAttempt)
        .filter(WordAttempt.user_id == user_id, WordAttempt.word_id == word_id)
        .order_by(WordAttempt.created_at, WordAttempt.id)
        .all()
    )
    lesson_ids = {a.lesson_id for a in attempts if a.lesson_id}
    phrase_ids = {a.phrase_id for a in attempts if a.phrase_id}
    mini_ids = {a.mini_phrase_id for a in attempts if a.mini_phrase_id}
    lessons = {l.id: l for l in db.query(Lesson).filter(Lesson.id.in_(lesson_ids))} if lesson_ids else {}
    phrases = {p.id: p.original for p in db.query(Phrase).filter(Phrase.id.in_(phrase_ids))} if phrase_ids else {}
    minis = {m.id: m.text for m in db.query(MiniPhrase).filter(MiniPhrase.id.in_(mini_ids))} if mini_ids else {}

    def out(a: WordAttempt) -> dict:
        return _attempt_out(a, lessons, phrases, minis)

    entries = (
        db.query(ReviewListWord, ReviewList)
        .join(ReviewList, ReviewList.id == ReviewListWord.list_id)
        .filter(ReviewList.user_id == user_id, ReviewListWord.word_id == word_id)
        .order_by(ReviewList.id.desc())
        .all()
    )
    lists = [
        {
            "list_id": rl.id,
            "status": rl.status,
            "created_at": rl.created_at,
            "activated_at": rl.activated_at,
            "closed_at": rl.closed_at,
            "position": e.position,
            "list_size": rl.size,
            "recall_at_entry": e.recall,
            "target": e.target,
            "stability_at_entry": e.stability,
            "difficulty_at_entry": e.difficulty,
            "last_review_at_entry": e.last_review,
            "review_days_at_entry": e.review_days,
            "score_at_entry": e.score,
            "done_at": e.done_at,
        }
        for e, rl in entries
    ]

    days = explain_days(attempts)
    by_exercise: dict[str, dict] = {}
    for a in attempts:
        b = by_exercise.setdefault(a.exercise_key, {"exercise_key": a.exercise_key, "total": 0, "errors": 0, "timeouts": 0})
        b["total"] += 1
        if not a.is_correct:
            b["errors"] += 1
        if a.timed_out:
            b["timeouts"] += 1
    errors = [a for a in attempts if not a.is_correct]

    return {
        "user_id": user.id,
        "user_login": user.login,
        "word_id": word.id,
        "word": word.word,
        "translation": _translation(word),
        "settings": settings,
        "state": {
            "score": progress.score if progress is not None else 0,
            "learned": progress is not None and progress.score >= settings["learned_threshold"],
            "recall_now": recall_probability(progress, now) if progress is not None else None,
            "stability": progress.memory_stability if progress is not None else None,
            "difficulty": progress.memory_difficulty if progress is not None else None,
            "last_review": progress.memory_last_review if progress is not None else None,
            "review_days": progress.memory_review_days if progress is not None else 0,
            "falls_below_at": falls_below_at(progress, settings["target"]) if progress is not None else None,
        },
        "lists": lists,
        "days": [
            {
                "day": d["day"],
                "first_at": d["first_at"],
                "grade": d["grade"],
                "reason": d["reason"],
                "recall_before": d["recall_before"],
                "days_since_previous": d["days_since_previous"],
                "stability_after": d["stability_after"],
                "difficulty_after": d["difficulty_after"],
                "correct": sum(1 for a in d["attempts"] if a.is_correct),
                "errors": sum(1 for a in d["attempts"] if not a.is_correct),
                "attempts": [out(a) for a in d["attempts"]],
            }
            for d in reversed(days)
        ],
        "errors_by_exercise": sorted(by_exercise.values(), key=lambda b: -b["errors"]),
        "recent_errors": [out(a) for a in reversed(errors[-15:])],
        "curve": recall_curve(attempts, now),
    }
