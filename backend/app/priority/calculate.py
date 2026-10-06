"""The one place a Priority Score is ever computed -- always on demand,
straight from WordProgress/WordLevel/WordAttempt plus the admin's own
band tables, never stored or cached. A word that hasn't been touched in
weeks must read as MORE urgent today than it did yesterday even with zero
new attempts, which a stored number could only do by being re-touched by
some background job -- computing it fresh every time makes that job
unnecessary and the number impossible to go stale.

Every weight and threshold is read from app/models/priority.py's tables
(see app/priority/settings.py) -- nothing below is a business constant.
This module only knows the SHAPE of the formula (four weighted factors,
summed), never the numbers themselves.

Words are scored in batches (calculate_priorities): the settings and band
tables are read once and every word's recent attempts come from one
query, so scoring a whole vocabulary costs a handful of queries rather
than several per word.
"""

from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.dates import utc_now
from app.models.priority import PriorityLevelBand, PriorityRecencyBand, PrioritySettings, PriorityStabilityBand
from app.models.word_attempt import WordAttempt
from app.models.word_level import WordLevel
from app.models.word_progress import WordProgress
from app.priority.settings import (
    get_priority_settings,
    ordered_priority_level_bands,
    ordered_recency_bands,
    ordered_stability_bands,
    priority_level_band_for_score,
    recency_band_for_days,
    stability_band_for_percent,
)
from app.word_levels import level_for_score_in, ordered_enabled_levels

# The 3 fixed windows "недавние ошибки" looks at (part 3.2 of the spec).
# Their SIZES are fixed by the spec's own wording ("последние 5/10/20
# попыток"); their WEIGHTS relative to each other are the admin-configured
# part (PrioritySettings.window5_weight etc.) -- see this module's own
# docstring on what counts as a business constant here and what doesn't.
ERROR_WINDOWS = (5, 10, 20)
# Nothing here ever looks further back than this many attempts per word.
ATTEMPTS_PER_WORD = 200


@dataclass
class PriorityResult:
    """Everything both the calculation itself and a diagnostics page need
    -- the final score/level plus every raw sub-signal that produced it,
    so "why is this word Critical" is always answerable, never a black
    box."""

    score: float
    level: PriorityLevelBand | None

    level_contribution: float
    recent_errors_contribution: float
    recency_contribution: float
    stability_contribution: float

    total_attempts: int
    days_since_last_attempt: int | None
    stability_percent: int | None
    stability_band: PriorityStabilityBand | None
    recency_band: PriorityRecencyBand | None
    last_attempt_at: datetime | None


@dataclass
class _Attempt:
    is_correct: bool
    created_at: datetime


@dataclass
class _Context:
    """Everything the formula needs that doesn't depend on the word."""

    settings: PrioritySettings
    levels: list[WordLevel]
    recency_bands: list[PriorityRecencyBand]
    stability_bands: list[PriorityStabilityBand]
    level_bands: list[PriorityLevelBand]
    now: datetime


def _load_context(db: Session) -> _Context:
    return _Context(
        settings=get_priority_settings(db),
        levels=ordered_enabled_levels(db),
        recency_bands=ordered_recency_bands(db),
        stability_bands=ordered_stability_bands(db),
        level_bands=ordered_priority_level_bands(db),
        now=utc_now(),
    )


def _error_rate(attempts_desc: list[_Attempt], window: int) -> float:
    """Fraction (0-1) of incorrect answers among the most recent `window`
    attempts -- 0 if there is no history at all (a word with zero
    attempts has nothing to be unstable about; the LEVEL factor is what
    flags a brand new word, not this one)."""
    window_attempts = attempts_desc[:window]
    if not window_attempts:
        return 0.0
    errors = sum(1 for a in window_attempts if not a.is_correct)
    return errors / len(window_attempts)


def _score(ctx: _Context, score: int, attempts_desc: list[_Attempt]) -> PriorityResult:
    settings = ctx.settings

    # --- 1. Уровень слова -------------------------------------------------
    level = level_for_score_in(ctx.levels, score)
    level_contribution = (level.priority_weight if level is not None else 0.0) * settings.weight_level

    # --- 2. Недавние ошибки ------------------------------------------------
    window_weights = {5: settings.window5_weight, 10: settings.window10_weight, 20: settings.window20_weight}
    total_window_weight = sum(window_weights.values())
    if total_window_weight > 0:
        weighted_error_rate = (
            sum(_error_rate(attempts_desc, w) * window_weights[w] for w in ERROR_WINDOWS) / total_window_weight
        )
    else:
        weighted_error_rate = 0.0
    recent_errors_contribution = weighted_error_rate * 100 * settings.weight_recent_errors

    # --- 3. Давность последнего контакта ------------------------------------
    last_attempt_at = attempts_desc[0].created_at if attempts_desc else None
    days_since_last_attempt: int | None = None
    recency_band: PriorityRecencyBand | None = None
    recency_contribution = 0.0
    if last_attempt_at is not None:
        days_since_last_attempt = (ctx.now - last_attempt_at).days
        recency_band = recency_band_for_days(ctx.recency_bands, days_since_last_attempt)
        recency_contribution = (recency_band.contribution if recency_band is not None else 0.0) * settings.weight_recency

    # --- 4. Стабильность ----------------------------------------------------
    # A separate, corrective factor from #2 above -- it reads the same
    # recent attempts but asks a different question (how STEADY are they,
    # not how many are wrong), so this never re-adds the same errors as a
    # second Priority contribution. Baseline is percent-correct over the
    # admin-configured window.
    stability_percent: int | None = None
    stability_band: PriorityStabilityBand | None = None
    stability_contribution = 0.0
    stability_window_attempts = attempts_desc[: settings.stability_window]
    if stability_window_attempts:
        correct = sum(1 for a in stability_window_attempts if a.is_correct)
        stability_percent = round(correct / len(stability_window_attempts) * 100)
        # Extension point: a future version could fold in the SEQUENCE of
        # stability_window_attempts here (e.g. count of correct<->incorrect
        # transitions) alongside stability_percent before picking a band --
        # today's version is the percent-only baseline the spec allows as
        # a reliable first step.
        stability_band = stability_band_for_percent(ctx.stability_bands, stability_percent)
        stability_contribution = (
            stability_band.contribution if stability_band is not None else 0.0
        ) * settings.weight_stability

    total_score = level_contribution + recent_errors_contribution + recency_contribution + stability_contribution

    return PriorityResult(
        score=round(total_score, 1),
        level=priority_level_band_for_score(ctx.level_bands, total_score),
        level_contribution=round(level_contribution, 1),
        recent_errors_contribution=round(recent_errors_contribution, 1),
        recency_contribution=round(recency_contribution, 1),
        stability_contribution=round(stability_contribution, 1),
        total_attempts=len(attempts_desc),
        days_since_last_attempt=days_since_last_attempt,
        stability_percent=stability_percent,
        stability_band=stability_band,
        recency_band=recency_band,
        last_attempt_at=last_attempt_at,
    )


def calculate_priorities(db: Session, user_id: int, word_ids: list[int]) -> dict[int, PriorityResult]:
    """word_id -> PriorityResult for every id given, in a fixed handful of
    queries however many words there are."""
    if not word_ids:
        return {}
    ids = list(set(word_ids))
    ctx = _load_context(db)

    scores = dict(
        db.query(WordProgress.word_id, WordProgress.score)
        .filter(WordProgress.user_id == user_id, WordProgress.word_id.in_(ids))
        .all()
    )

    # Newest first, at most ATTEMPTS_PER_WORD per word -- every sub-signal
    # (windows, stability, recency) only ever needs a prefix of that.
    rank = (
        func.row_number()
        .over(partition_by=WordAttempt.word_id, order_by=(WordAttempt.created_at.desc(), WordAttempt.id.desc()))
        .label("rank")
    )
    recent = (
        select(WordAttempt.word_id, WordAttempt.is_correct, WordAttempt.created_at, rank)
        .where(WordAttempt.user_id == user_id, WordAttempt.word_id.in_(ids))
        .subquery()
    )
    attempts: dict[int, list[_Attempt]] = defaultdict(list)
    for word_id, is_correct, created_at in db.execute(
        select(recent.c.word_id, recent.c.is_correct, recent.c.created_at)
        .where(recent.c.rank <= ATTEMPTS_PER_WORD)
        .order_by(recent.c.word_id, recent.c.rank)
    ):
        attempts[word_id].append(_Attempt(is_correct, created_at))

    results = {word_id: _score(ctx, scores.get(word_id, 0), attempts.get(word_id, [])) for word_id in ids}
    if ctx.settings.memory_enabled:
        _apply_memory(db, user_id, ids, results, ctx)
    return results


def _apply_memory(db: Session, user_id: int, ids: list[int], results: dict, ctx: "_Context") -> None:
    """With the memory model on, the level comes from the recall
    probability R, mapped onto the admin's level bands by rank (Критический
    = the top band, ..., Минимальный = the bottom one) and the score is the
    chance of forgetting, 0-100. A word with no reviews yet has no level."""
    from app.memory import recall_probability
    from app.priority.settings import priority_role_bands

    roles = priority_role_bands(db)
    s = ctx.settings
    progress = {
        p.word_id: p for p in db.query(WordProgress).filter(WordProgress.user_id == user_id, WordProgress.word_id.in_(ids))
    }
    for word_id, result in results.items():
        p = progress.get(word_id)
        r = recall_probability(p, ctx.now) if p is not None else None
        if r is None:
            result.level = None
            continue
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


def calculate_priority(db: Session, user_id: int, word_id: int) -> PriorityResult:
    return calculate_priorities(db, user_id, [word_id])[word_id]
