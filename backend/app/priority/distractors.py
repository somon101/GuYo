"""Wrong-answer/distractor selection's one Priority-aware step, shared by
every round builder that draws a fake option from a user's already-
learned words (app/exercises/true_or_false.py, app/quests/rounds.py's
_siblings and build_true_or_false_round).
"""

import random

from sqlalchemy.orm import Session

from app.models.word import Word
from app.priority.calculate import calculate_priority
from app.priority.settings import priority_role_bands


def prefer_distractor_words(db: Session, user_id: int, words: list[Word]) -> list[Word]:
    """Reorders an already-computed learned-word candidate pool for use as
    distractor material, filling from Priority tiers in strict order --
    Low first, only topping up from Minimal once Low runs out (e.g. need
    3, Low only has 1: take that 1, then take 2 from Minimal) -- never
    the two blended into one shuffled pool. Everything else in between is
    a fallback tier, and Critical-priority words are excluded outright
    (never confuse the user with a word they're actively struggling with
    right now).

    Never returns an empty list when given a non-empty one, and never
    raises -- a caller that gets an empty `words` back from its own query
    gets an empty list back here too, same as before Priority existed.
    Only if EVERY single candidate happens to be Critical does this fall
    back to including them anyway, rather than leave the caller with no
    distractor at all."""
    if not words:
        return []

    roles = priority_role_bands(db)
    critical_id = roles["critical"].id if roles["critical"] is not None else None
    low_id = roles["low"].id if roles["low"] is not None else None
    minimal_id = roles["minimal"].id if roles["minimal"] is not None else None

    low: list[Word] = []
    minimal: list[Word] = []
    acceptable: list[Word] = []
    critical_only: list[Word] = []
    for word in words:
        level = calculate_priority(db, user_id, word.id).level
        level_id = level.id if level is not None else None
        if critical_id is not None and level_id == critical_id:
            critical_only.append(word)
        elif low_id is not None and level_id == low_id:
            low.append(word)
        elif minimal_id is not None and level_id == minimal_id:
            minimal.append(word)
        else:
            acceptable.append(word)

    random.shuffle(low)
    random.shuffle(minimal)
    random.shuffle(acceptable)
    random.shuffle(critical_only)

    ordered = low + minimal + acceptable
    return ordered if ordered else critical_only
