"""The memory model: how likely a user is to recall a word right now.

Built on FSRS (py-fsrs, MIT): each (user, word) pair has a stability S --
days until the chance of recall falls to 90% -- and a difficulty D, and the
recall probability R decays with time since the last review. GuYo's own
layer on top decides what counts as one review and how good it was:

- One Asia/Dushanbe calendar day is one review. A lesson runs every word
  through several exercises within minutes; answers that close together
  barely strengthen long-term memory, so they are judged together.
- The day's grade comes from what the answers prove. A real wrong answer
  means the word wasn't recalled (Again). Getting everything right only
  in recognition exercises -- where the options can be eliminated or
  guessed -- is weaker evidence (Hard) than producing the word in a recall
  exercise (Good). A day whose only misses were timeouts counts as Hard:
  slow, not forgotten.

State is always rebuilt from the full answer history (never patched
incrementally), so it cannot drift from the attempts that produced it.

For now the model runs alongside the existing Priority system and drives
nothing yet: it is computed and stored so its predictions can be checked
against real outcomes before anything relies on it.
"""

from collections import OrderedDict
from datetime import datetime, timezone

from fsrs import Card, Rating, Scheduler, State
from sqlalchemy import and_, func
from sqlalchemy.orm import Session

from app.core.dates import DUSHANBE_TZ, utc_now
from app.models.word_attempt import WordAttempt
from app.models.word_progress import WordProgress

DESIRED_RETENTION = 0.9
RECALL_EXERCISES = {"build_word", "speaking_word"}

# Day-level reviews: no minute-scale learning steps, no random interval
# fuzz -- the model must be a deterministic function of the history.
_scheduler = Scheduler(
    desired_retention=DESIRED_RETENTION,
    learning_steps=(),
    relearning_steps=(),
    enable_fuzzing=False,
)


def _utc(value: datetime) -> datetime:
    """py-fsrs only accepts timezone-aware UTC datetimes."""
    return value.astimezone(timezone.utc)


def day_grade(attempts: list[WordAttempt]) -> Rating:
    real_misses = [a for a in attempts if not a.is_correct and not a.timed_out]
    if real_misses:
        return Rating.Again
    if any(a.timed_out for a in attempts):
        return Rating.Hard
    if any(a.exercise_key in RECALL_EXERCISES for a in attempts):
        return Rating.Good
    return Rating.Hard


def _days(attempts: list[WordAttempt]) -> "OrderedDict[object, list[WordAttempt]]":
    days: OrderedDict = OrderedDict()
    for a in attempts:
        days.setdefault(a.created_at.astimezone(DUSHANBE_TZ).date(), []).append(a)
    return days


def replay(attempts: list[WordAttempt], until: datetime | None = None) -> tuple[Card | None, int]:
    """The card after every review day strictly before `until` (all of
    them when None), and how many review days that was."""
    card = Card()
    count = 0
    for day, day_attempts in _days(attempts).items():
        first = day_attempts[0].created_at
        if until is not None and first >= until:
            break
        card, _ = _scheduler.review_card(card, day_grade(day_attempts), review_datetime=_utc(first))
        count += 1
    return (card if count else None), count


def recall_probability(progress: WordProgress, now: datetime | None = None) -> float | None:
    """R for this pair right now; None when the pair has no reviews yet."""
    if progress.memory_stability is None or progress.memory_last_review is None:
        return None
    card = Card(
        state=State.Review,
        stability=progress.memory_stability,
        difficulty=progress.memory_difficulty,
        last_review=_utc(progress.memory_last_review),
    )
    return _scheduler.get_card_retrievability(card, _utc(now or utc_now()))


def rebuild_memory(db: Session, progress: WordProgress) -> None:
    """Recomputes this pair's memory state from its whole answer history.
    Does NOT commit -- the caller owns the transaction."""
    attempts = (
        db.query(WordAttempt)
        .filter(WordAttempt.user_id == progress.user_id, WordAttempt.word_id == progress.word_id)
        .order_by(WordAttempt.created_at, WordAttempt.id)
        .all()
    )
    card, count = replay(attempts)
    progress.memory_review_days = count
    if card is None:
        progress.memory_stability = progress.memory_difficulty = progress.memory_last_review = None
        return
    progress.memory_stability = card.stability
    progress.memory_difficulty = card.difficulty
    progress.memory_last_review = card.last_review


def rebuild_pending_memories(db: Session, limit: int = 500) -> int:
    """Models pairs that have answers but no memory state yet -- the
    one-time backfill of history recorded before the model existed, done
    a batch at a time by the scheduler. Commits each batch."""
    has_attempts = (
        db.query(WordAttempt.id)
        .filter(and_(WordAttempt.user_id == WordProgress.user_id, WordAttempt.word_id == WordProgress.word_id))
        .exists()
    )
    pending = (
        db.query(WordProgress)
        .filter(WordProgress.memory_last_review.is_(None), has_attempts)
        .limit(limit)
        .all()
    )
    for progress in pending:
        rebuild_memory(db, progress)
    db.commit()
    return len(pending)


def memory_coverage(db: Session) -> tuple[int, int]:
    """(modelled pairs, pairs with at least one answer)."""
    modelled = db.query(func.count(WordProgress.id)).filter(WordProgress.memory_last_review.isnot(None)).scalar()
    total = db.query(func.count(func.distinct(func.concat(WordAttempt.user_id, "-", WordAttempt.word_id)))).scalar()
    return modelled or 0, total or 0


def secured_word_ids(db: Session, user_id: int, word_ids: list[int] | None, threshold: int) -> set[int]:
    """Words that need no more work in a lesson: learned by score AND, while
    the memory model is on, still remembered (R at or above the target).
    A learned word the user is forgetting needs work again -- it goes back
    into lessons and stays there until a review brings R back up. A pair
    with no memory data yet is judged by score alone. `word_ids=None`
    means every word this user has progress on."""
    from app.priority.settings import get_priority_settings

    settings = get_priority_settings(db)
    query = db.query(WordProgress).filter(WordProgress.user_id == user_id, WordProgress.score >= threshold)
    if word_ids is not None:
        if not word_ids:
            return set()
        query = query.filter(WordProgress.word_id.in_(word_ids))
    rows = query.all()
    if not settings.memory_enabled:
        return {p.word_id for p in rows}
    now = utc_now()
    secured = set()
    for p in rows:
        r = recall_probability(p, now)
        if r is None or r >= settings.memory_target_retention:
            secured.add(p.word_id)
    return secured
