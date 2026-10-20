"""The one place a word's Priority is ever computed -- always on demand,
never stored or cached. It comes from the memory model: the chance the
learner still remembers the word now (recall probability R), mapped onto
the admin's named level bands (Критический ... Минимальный) by the R
cut-offs in PrioritySettings. A word that hasn't been touched in weeks
reads as more urgent today than yesterday with no new answers, because R
keeps falling.

Words are computed in batches (calculate_priorities), so a whole vocabulary
costs a handful of queries rather than several per word.
"""

from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.dates import utc_now
from app.models.priority import PriorityLevelBand
from app.models.word_attempt import WordAttempt
from app.models.word_progress import WordProgress
from app.priority.settings import get_priority_settings, priority_role_bands


@dataclass
class PriorityResult:
    """A word's Priority plus the answer history behind it, for the
    diagnostics page."""

    score: float  # chance of forgetting, 0-100
    level: PriorityLevelBand | None  # None: no answers yet
    total_attempts: int
    days_since_last_attempt: int | None
    last_attempt_at: datetime | None


def calculate_priorities(db: Session, user_id: int, word_ids: list[int]) -> dict[int, PriorityResult]:
    """word_id -> PriorityResult for every id given, in a fixed handful of
    queries however many words there are."""
    if not word_ids:
        return {}
    from app.memory import recall_probability

    ids = list(set(word_ids))
    now = utc_now()
    s = get_priority_settings(db)
    roles = priority_role_bands(db)

    history = {
        word_id: (count, last)
        for word_id, count, last in db.query(WordAttempt.word_id, func.count(WordAttempt.id), func.max(WordAttempt.created_at))
        .filter(WordAttempt.user_id == user_id, WordAttempt.word_id.in_(ids))
        .group_by(WordAttempt.word_id)
    }
    progress = {
        p.word_id: p for p in db.query(WordProgress).filter(WordProgress.user_id == user_id, WordProgress.word_id.in_(ids))
    }

    results = {}
    for word_id in ids:
        count, last = history.get(word_id, (0, None))
        result = PriorityResult(
            score=0.0,
            level=None,
            total_attempts=count,
            days_since_last_attempt=(now - last).days if last is not None else None,
            last_attempt_at=last,
        )
        p = progress.get(word_id)
        r = recall_probability(p, now) if p is not None else None
        if r is not None:
            if r < s.memory_critical_below:
                role = "critical"
            elif r < s.memory_high_below:
                role = "high"
            elif r < s.memory_target_retention:
                role = "medium"
            elif r < s.memory_minimal_above:
                role = "low"
            else:
                role = "minimal"
            result.level = roles[role]
            result.score = round((1 - r) * 100, 1)
        results[word_id] = result
    return results


def calculate_priority(db: Session, user_id: int, word_id: int) -> PriorityResult:
    return calculate_priorities(db, user_id, [word_id])[word_id]
