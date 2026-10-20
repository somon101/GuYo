"""How well does the memory model predict forgetting?

The test set is honest by construction: for every (user, word) pair, every
review day after its first one, the FIRST answer of that day -- the moment
the user meets the word again, before any same-day practice -- is the
outcome to predict, from the recall probability R the model gives at that
moment (only the history before it is seen).

AUC says how well R RANKS words; log loss and the calibration table check
whether R is a trustworthy probability.
"""

import math
from collections import defaultdict
from dataclasses import dataclass

from sqlalchemy.orm import Session

from app.memory.service import _days, _scheduler, _utc, replay
from app.models.word_attempt import WordAttempt


@dataclass
class _Case:
    correct: bool
    recall: float
    exercise_key: str


def _auc(scores: list[float], labels: list[bool]) -> float | None:
    """Probability that a randomly chosen positive outranks a randomly
    chosen negative (ties count half)."""
    pos = sum(labels)
    neg = len(labels) - pos
    if not pos or not neg:
        return None
    ranked = sorted(zip(scores, labels), key=lambda x: x[0])
    rank_sum, i = 0.0, 0
    while i < len(ranked):
        j = i
        while j < len(ranked) and ranked[j][0] == ranked[i][0]:
            j += 1
        avg_rank = (i + j + 1) / 2
        rank_sum += avg_rank * sum(1 for k in range(i, j) if ranked[k][1])
        i = j
    return (rank_sum - pos * (pos + 1) / 2) / (pos * neg)


def evaluate(db: Session, max_pairs: int = 20000) -> dict:
    rows = (
        db.query(WordAttempt)
        .order_by(WordAttempt.user_id, WordAttempt.word_id, WordAttempt.created_at, WordAttempt.id)
        .all()
    )
    by_pair: dict[tuple[int, int], list[WordAttempt]] = defaultdict(list)
    for a in rows:
        by_pair[(a.user_id, a.word_id)].append(a)

    cases: list[_Case] = []
    for attempts in list(by_pair.values())[:max_pairs]:
        days = list(_days(attempts).values())
        for day_attempts in days[1:]:
            first = day_attempts[0]
            before = [a for a in attempts if a.created_at < first.created_at]
            card, _ = replay(before)
            recall = _scheduler.get_card_retrievability(card, _utc(first.created_at))
            cases.append(_Case(first.is_correct and not first.timed_out, recall, first.exercise_key))

    labels = [c.correct for c in cases]
    eps = 1e-6
    log_loss = (
        -sum(math.log(max(eps, c.recall)) if c.correct else math.log(max(eps, 1 - c.recall)) for c in cases) / len(cases)
        if cases
        else None
    )
    base_rate = sum(labels) / len(labels) if labels else None
    base_log_loss = (
        -(base_rate * math.log(base_rate) + (1 - base_rate) * math.log(1 - base_rate))
        if base_rate not in (None, 0, 1)
        else None
    )

    calibration = []
    for lo, hi in ((0, 0.5), (0.5, 0.7), (0.7, 0.8), (0.8, 0.9), (0.9, 0.95), (0.95, 1.01)):
        bucket = [c for c in cases if lo <= c.recall < hi]
        if bucket:
            calibration.append({
                "predicted": f"{round(lo * 100)}–{min(100, round(hi * 100))}%",
                "answers": len(bucket),
                "mean_predicted": round(sum(c.recall for c in bucket) / len(bucket), 3),
                "actually_correct": round(sum(c.correct for c in bucket) / len(bucket), 3),
            })

    by_exercise = {}
    for key in sorted({c.exercise_key for c in cases}):
        subset = [c for c in cases if c.exercise_key == key]
        by_exercise[key] = {
            "answers": len(subset),
            "auc_memory": _auc([c.recall for c in subset], [c.correct for c in subset]),
        }

    return {
        "pairs_with_answers": len(by_pair),
        "test_answers": len(cases),
        "share_correct": base_rate,
        "auc_memory": _auc([c.recall for c in cases], labels),
        "log_loss_memory": log_loss,
        "log_loss_always_average": base_log_loss,
        "calibration": calibration,
        "by_exercise": by_exercise,
    }
