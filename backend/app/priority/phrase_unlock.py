"""Which words open phrases soonest -- for the automatic word pick of a new
lesson (app/routers/lessons.py's prioritized_words).

A phrase («Мои фразы») or mini-phrase that is still closed needs some words
the learner hasn't learned yet. Each such word gets credit for it: the fewer
words the phrase still lacks, the more each one is worth (1 missing → +1,
2 → +0.5, 3 → +0.33; phrases lacking more are too far away to count). The
"what's missing" rules are the same ones Admin Web's phrase analytics uses
(app/routers/admin_analytics.py), so both always agree.
"""

from sqlalchemy.orm import Session

from app.models.dictionary import Dictionary
from app.models.mini_phrase import MiniPhrase
from app.models.phrase import Phrase
from app.models.user import User

MAX_MISSING = 3
# Share of a lesson's free slots (after words being forgotten) given to the
# words that open the most phrases; the rest keep the goal/importance order.
PHRASE_UNLOCK_SHARE = 0.34


def phrase_unlock_scores(db: Session, user: User, dictionary: Dictionary) -> dict[int, float]:
    from app.mini_phrases.service import _learned_word_ids
    from app.routers.admin_analytics import _build_token_to_word, _get_learned_word_tokens, _phrase_progress

    scores: dict[int, float] = {}

    def credit(word_ids: list[int]) -> None:
        if 0 < len(word_ids) <= MAX_MISSING:
            for wid in word_ids:
                scores[wid] = scores.get(wid, 0.0) + 1.0 / len(word_ids)

    learned_tokens = _get_learned_word_tokens(db, user.id, dictionary)
    token_to_word, _ = _build_token_to_word(db, dictionary)
    for phrase in db.query(Phrase).filter(Phrase.dictionary_id == dictionary.id):
        _total, _learned, missing = _phrase_progress(phrase, learned_tokens, token_to_word)
        if missing and all(wid is not None for wid, _ in missing):
            credit([wid for wid, _ in missing])

    learned = _learned_word_ids(db, user.id, dictionary.id)
    for mp in db.query(MiniPhrase).filter(MiniPhrase.dictionary_id == dictionary.id, MiniPhrase.enabled.is_(True)):
        credit(list({p.word_id for p in mp.parts if p.word_id not in learned}))
    return scores
