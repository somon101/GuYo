"""A learner's step-by-step history for Admin Web's «История»: every
answer (WordAttempt, with what was actually given) merged with every
non-answer step (UserEvent) into one timeline, plus a short summary.

Server-side steps are logged where they happen (lesson created/completed,
personal quest created, quest answered); the app reports the rest through
POST /events (CLIENT_KINDS). Nothing here feeds back into learning logic.
"""

from collections import Counter
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.models.lesson import Lesson
from app.models.user_event import UserEvent
from app.models.word import Word
from app.models.word_attempt import WordAttempt

# Reported by the app; anything else sent to POST /events is rejected.
CLIENT_KINDS = ("app_opened", "lesson_opened", "lesson_left", "quest_opened", "quest_left")


def log_event(db: Session, user_id: int, kind: str, *, lesson_id=None, quest_id=None, data=None) -> None:
    """Adds one event; never commits (the caller owns the transaction)."""
    db.add(UserEvent(user_id=user_id, kind=kind, lesson_id=lesson_id, quest_id=quest_id, data=data))


def _tajik(word: Word | None) -> str | None:
    if word is None:
        return None
    return next((t.text for t in word.translations if t.language == "tg"), None)


def build_history(db: Session, user_id: int, days: int) -> dict:
    since = datetime.now(timezone.utc) - timedelta(days=days)
    attempts = (
        db.query(WordAttempt)
        .filter(WordAttempt.user_id == user_id, WordAttempt.created_at >= since)
        .order_by(WordAttempt.created_at)
        .all()
    )
    events = (
        db.query(UserEvent)
        .filter(UserEvent.user_id == user_id, UserEvent.created_at >= since)
        .order_by(UserEvent.created_at)
        .all()
    )
    word_ids = {a.word_id for a in attempts}
    words = {w.id: w for w in db.query(Word).filter(Word.id.in_(word_ids)).all()} if word_ids else {}
    lesson_ids = {a.lesson_id for a in attempts if a.lesson_id} | {e.lesson_id for e in events if e.lesson_id}
    lesson_numbers = (
        {l.id: l.number for l in db.query(Lesson).filter(Lesson.id.in_(lesson_ids)).all()} if lesson_ids else {}
    )

    items = []
    for a in attempts:
        word = words.get(a.word_id)
        items.append(
            {
                "at": a.created_at,
                "kind": "answer",
                "source": a.source,
                "exercise_key": a.exercise_key,
                "word_id": a.word_id,
                "word": word.word if word else None,
                "translation": _tajik(word),
                "is_correct": a.is_correct,
                "given_answer": a.given_answer,
                "timed_out": a.timed_out,
                "duration_ms": a.duration_ms,
                "score_after": a.score_after,
                "lesson_id": a.lesson_id,
                "lesson_number": lesson_numbers.get(a.lesson_id),
            }
        )
    for e in events:
        items.append(
            {
                "at": e.created_at,
                "kind": e.kind,
                "lesson_id": e.lesson_id,
                "lesson_number": lesson_numbers.get(e.lesson_id),
                "quest_id": e.quest_id,
                "data": e.data or {},
            }
        )
    items.sort(key=lambda i: i["at"], reverse=True)

    kinds = Counter(e.kind for e in events)
    quest_answers = [e for e in events if e.kind == "quest_answered" and (e.data or {}).get("personal")]
    wrong = Counter(a.word_id for a in attempts if not a.is_correct)
    return {
        "days": days,
        "summary": {
            "answers": len(attempts),
            "correct": sum(a.is_correct for a in attempts),
            "timed_out": sum(a.timed_out for a in attempts),
            "lessons_created": kinds["lesson_created"],
            "adaptive_lessons_created": sum(
                1 for e in events if e.kind == "lesson_created" and (e.data or {}).get("adaptive")
            ),
            "lessons_completed": kinds["lesson_completed"],
            "lessons_left": kinds["lesson_left"],
            "personal_quests_created": kinds["personal_quest_created"],
            "personal_quest_answers": len(quest_answers),
            "personal_quest_correct": sum(1 for e in quest_answers if e.data.get("correct")),
            "app_opens": kinds["app_opened"],
            "top_mistakes": [
                {
                    "word_id": wid,
                    "word": words[wid].word if wid in words else None,
                    "translation": _tajik(words.get(wid)),
                    "wrong": n,
                }
                for wid, n in wrong.most_common(10)
            ],
        },
        "items": items[:1000],
    }
