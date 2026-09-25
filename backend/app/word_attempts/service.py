"""The one place a WordAttempt row is ever created. Called from exactly
the two places a real answer is scored -- app/routers/lessons.py's
submit_answer and app/routers/quests.py's submit_quest_answer -- so an
attempt is recorded once, from the same call that already computed the
new score, never re-derived or duplicated anywhere else.
"""

from sqlalchemy.orm import Session

from app.models.word_attempt import WordAttempt


def record_word_attempt(
    db: Session, *, user_id: int, word_id: int, exercise_key: str, is_correct: bool, score_after: int
) -> None:
    """Logs one real answer for Admin Web's «Аналитика» -- purely additive
    bookkeeping alongside whatever the caller already did to WordProgress/
    achievements/rating; this never reads or changes any of those itself,
    and never needs to (an attempt is simply a fact that happened, not a
    decision). Deliberately does NOT commit: the caller owns the
    transaction, same contract as achievements/rating's own service
    functions."""
    db.add(
        WordAttempt(
            user_id=user_id,
            word_id=word_id,
            exercise_key=exercise_key,
            is_correct=is_correct,
            score_after=score_after,
        )
    )
    db.flush()
