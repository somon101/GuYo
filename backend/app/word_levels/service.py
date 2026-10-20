"""Word-level ladder logic: which level the memory model puts a word at.
Entirely separate from rating (Rank).
"""

from sqlalchemy.orm import Session

from app.models.word_level import WordLevel


def ordered_enabled_levels(db: Session) -> list[WordLevel]:
    """Every enabled level, weakest memory first -- the order that decides a
    word's level and the app's red-to-green badge position, independent of
    the admin's own display `order`."""
    return db.query(WordLevel).filter(WordLevel.enabled.is_(True)).order_by(WordLevel.min_days, WordLevel.id).all()


def memory_level_in(levels: list[WordLevel], progress, now=None, settings=None) -> WordLevel | None:
    """A word's level from the memory model, against an already-fetched
    ladder (ordered_enabled_levels): the highest level whose `min_days` its
    memory holds (FSRS stability), one level lower while the word is being
    forgotten (recall below the target) and two lower when badly forgotten
    (below the critical mark) -- reviewing it brings the level straight back.
    None for a word never answered (no memory yet)."""
    if not levels or progress is None or progress.memory_stability is None:
        return None
    from app.memory.service import recall_probability

    index = 0
    for i, level in enumerate(levels):
        if progress.memory_stability >= level.min_days:
            index = i
    if settings is not None:
        r = recall_probability(progress, now)
        if r is not None and r < settings.memory_critical_below:
            index -= 2
        elif r is not None and r < settings.memory_target_retention:
            index -= 1
    return levels[max(0, index)]


def memory_levels_for(db: Session, user_id: int, word_ids) -> dict[int, WordLevel | None]:
    """word_id -> its memory level, for many words with three queries."""
    from app.core.dates import utc_now
    from app.models.word_progress import WordProgress
    from app.priority.settings import get_priority_settings

    word_ids = list(word_ids)
    if not word_ids:
        return {}
    levels = ordered_enabled_levels(db)
    settings = get_priority_settings(db)
    now = utc_now()
    rows = {
        p.word_id: p
        for p in db.query(WordProgress).filter(WordProgress.user_id == user_id, WordProgress.word_id.in_(word_ids))
    }
    return {w: memory_level_in(levels, rows.get(w), now, settings) for w in word_ids}
