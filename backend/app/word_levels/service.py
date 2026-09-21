"""Word-level ladder logic -- mirrors app/rating/service.py's Rank
functions exactly (current_rank_for_points / assert_rank_range_free),
applied to WordLevel instead. Entirely separate from rating: nothing here
reads or writes UserRating/Rank, and nothing in app/rating/ reads or
writes WordLevel.
"""

from sqlalchemy.orm import Session

from app.models.word_level import WordLevel


def level_for_score(db: Session, score: int) -> WordLevel | None:
    """The one place a word's level is ever determined -- purely a
    comparison against enabled WordLevels' own [min_points, max_points]
    ranges, never a stored/cached value (WordProgress.score is the only
    thing that's ever persisted; level is always re-derived from it, so a
    word can move up AND down as its score changes -- see
    app/routers/lessons.py's submit_answer). Returns None if no enabled
    level's range covers `score` (e.g. no levels configured yet)."""
    levels = db.query(WordLevel).filter(WordLevel.enabled.is_(True)).order_by(WordLevel.min_points, WordLevel.id).all()
    for level in levels:
        if level.min_points <= score and (level.max_points is None or score <= level.max_points):
            return level
    return None


def top_level_threshold(db: Session) -> int | None:
    """The min_points of the highest-scoring enabled level -- this becomes
    the new "is this word learned" threshold (level 5 / "Закреплено" in
    the spec's own example), replacing the old single LearningSettings
    number. None if no levels are configured yet, so the caller can fall
    back to the legacy setting during the transition."""
    top = db.query(WordLevel).filter(WordLevel.enabled.is_(True)).order_by(WordLevel.min_points.desc()).first()
    return top.min_points if top is not None else None


def levels_overlap(a_min: int, a_max: int | None, b_min: int, b_max: int | None) -> bool:
    a_hi = a_max if a_max is not None else float("inf")
    b_hi = b_max if b_max is not None else float("inf")
    return a_min <= b_hi and b_min <= a_hi


def assert_level_range_free(
    db: Session, *, min_points: int, max_points: int | None, enabled: bool, exclude_id: int | None = None
) -> None:
    """Raises ValueError if an enabled level with this range would overlap
    another already-enabled level's range -- same rule as Rank ranges."""
    if not enabled:
        return
    query = db.query(WordLevel).filter(WordLevel.enabled.is_(True))
    if exclude_id is not None:
        query = query.filter(WordLevel.id != exclude_id)
    for other in query.all():
        if levels_overlap(min_points, max_points, other.min_points, other.max_points):
            raise ValueError(f"Диапазон пересекается с уровнем «{other.name}»")
