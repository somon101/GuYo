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
"""

from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import desc
from sqlalchemy.orm import Session

from app.core.dates import utc_now
from app.models.priority import PriorityLevelBand, PriorityRecencyBand, PriorityStabilityBand
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
from app.word_levels import level_for_score

# The 3 fixed windows "недавние ошибки" looks at (part 3.2 of the spec).
# Their SIZES are fixed by the spec's own wording ("последние 5/10/20
# попыток"); their WEIGHTS relative to each other are the admin-configured
# part (PrioritySettings.window5_weight etc.) -- see this module's own
# docstring on what counts as a business constant here and what doesn't.
ERROR_WINDOWS = (5, 10, 20)


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


def _error_rate(attempts_desc: list[WordAttempt], window: int) -> float:
    """Fraction (0-1) of incorrect answers among the most recent `window`
    attempts -- 0 if there is no history at all (a word with zero
    attempts has nothing to be unstable about; the LEVEL factor is what
    flags a brand new word, not this one)."""
    window_attempts = attempts_desc[:window]
    if not window_attempts:
        return 0.0
    errors = sum(1 for a in window_attempts if not a.is_correct)
    return errors / len(window_attempts)


def calculate_priority(db: Session, user_id: int, word_id: int) -> PriorityResult:
    settings = get_priority_settings(db)

    progress = db.query(WordProgress).filter(WordProgress.user_id == user_id, WordProgress.word_id == word_id).first()
    score = progress.score if progress is not None else 0

    # Newest first -- every sub-signal below (windows, stability, recency)
    # only ever needs a prefix of this one already-ordered query, so it is
    # fetched once. Capped generously above the largest window (20) since
    # nothing here ever looks further back than that.
    attempts_desc: list[WordAttempt] = (
        db.query(WordAttempt)
        .filter(WordAttempt.user_id == user_id, WordAttempt.word_id == word_id)
        .order_by(desc(WordAttempt.created_at))
        .limit(200)
        .all()
    )
    total_attempts = len(attempts_desc)

    # --- 1. Уровень слова -------------------------------------------------
    level: WordLevel | None = level_for_score(db, score)
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
        days_since_last_attempt = (utc_now() - last_attempt_at).days
        recency_band = recency_band_for_days(ordered_recency_bands(db), days_since_last_attempt)
        recency_contribution = (recency_band.contribution if recency_band is not None else 0.0) * settings.weight_recency

    # --- 4. Стабильность ----------------------------------------------------
    # A separate, corrective factor from #2 above -- it reads the same
    # recent attempts but asks a different question (how STEADY are they,
    # not how many are wrong), so this never re-adds the same errors as a
    # second Priority contribution. Baseline is percent-correct over the
    # admin-configured window; see this function's own note below for
    # where a sequence-aware refinement (run-length / transition count)
    # would plug in without changing anything else in this file.
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
        stability_band = stability_band_for_percent(ordered_stability_bands(db), stability_percent)
        stability_contribution = (
            stability_band.contribution if stability_band is not None else 0.0
        ) * settings.weight_stability

    total_score = level_contribution + recent_errors_contribution + recency_contribution + stability_contribution
    priority_level = priority_level_band_for_score(ordered_priority_level_bands(db), total_score)

    return PriorityResult(
        score=round(total_score, 1),
        level=priority_level,
        level_contribution=round(level_contribution, 1),
        recent_errors_contribution=round(recent_errors_contribution, 1),
        recency_contribution=round(recency_contribution, 1),
        stability_contribution=round(stability_contribution, 1),
        total_attempts=total_attempts,
        days_since_last_attempt=days_since_last_attempt,
        stability_percent=stability_percent,
        stability_band=stability_band,
        recency_band=recency_band,
        last_attempt_at=last_attempt_at,
    )
