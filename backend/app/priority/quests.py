"""Quest word selection's one Priority-aware step: prefer High, then
Medium, before falling back to whatever pick_quest_word already did.
"""

import random

from sqlalchemy.orm import Session

from app.models.word import Word
from app.priority.calculate import calculate_priority
from app.priority.settings import priority_role_bands


def order_candidates_by_priority(db: Session, user_id: int, words: list[Word]) -> list[Word]:
    """Reorders `words` (a quest's already-eligible/feasible-filtered
    candidate pool -- see app.quests.service.pick_quest_word, the only
    caller) so High-priority words come first, then Medium, THEN every
    other candidate -- each group shuffled independently, so within a
    group the pick is still random, same as before this existed.

    Never shrinks the pool and never raises: a quest with no High or
    Medium candidate right now still gets a word from `rest`, exactly as
    it would have without Priority. This is a preference, not a filter."""
    roles = priority_role_bands(db)
    high_id = roles["high"].id if roles["high"] is not None else None
    medium_id = roles["medium"].id if roles["medium"] is not None else None

    high: list[Word] = []
    medium: list[Word] = []
    rest: list[Word] = []
    for word in words:
        level = calculate_priority(db, user_id, word.id).level
        level_id = level.id if level is not None else None
        if high_id is not None and level_id == high_id:
            high.append(word)
        elif medium_id is not None and level_id == medium_id:
            medium.append(word)
        else:
            rest.append(word)

    random.shuffle(high)
    random.shuffle(medium)
    random.shuffle(rest)
    return high + medium + rest
