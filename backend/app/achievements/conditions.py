"""One function per condition_type, each computing a user's CURRENT numeric
value for that measure. Registering a future condition_type (words
learned, lessons completed, exercises done, ...) is one new function here
plus one new entry in CONDITION_TYPES -- nothing in app/routers/
admin_achievements.py, the Achievement model, or the granting service
needs to change.
"""

from sqlalchemy.orm import Session

from app.models.dictionary import Dictionary
from app.models.phrase import Phrase
from app.models.user import User


def phrases_opened_count(db: Session, user: User) -> int:
    """How many phrases (across every dictionary, not just the one the
    user currently has selected) are available to this user right now --
    reuses the EXACT same per-dictionary availability logic "Мои фразы"
    and Admin Web's "Аналитика пользователей" already use (see
    app/routers/phrases.py's _get_learned_word_tokens/_phrase_is_available)
    rather than a second definition of "opened phrase"."""
    from app.routers.phrases import _get_learned_word_tokens, _phrase_is_available

    dictionary_ids = {row[0] for row in db.query(Phrase.dictionary_id).distinct().all()}
    total = 0
    for dictionary_id in dictionary_ids:
        dictionary = db.get(Dictionary, dictionary_id)
        if dictionary is None:
            continue
        learned_tokens = _get_learned_word_tokens(db, user.id, dictionary)
        phrases = db.query(Phrase).filter(Phrase.dictionary_id == dictionary_id).all()
        total += sum(1 for p in phrases if _phrase_is_available(p, learned_tokens))
    return total


# condition_type -> (db, user) -> current value. The one place a new
# condition_type becomes usable by both the granting service and the
# "current progress" numbers shown in the Profile screen.
CONDITION_TYPES = {
    "phrases_opened": phrases_opened_count,
}

# condition_type -> a human label for Admin Web's picker -- kept alongside
# CONDITION_TYPES rather than merged into it, since Flutter/the granting
# service never need this text, only Admin Web's UI does.
CONDITION_TYPE_LABELS: dict[str, str] = {
    "phrases_opened": "Количество открытых фраз",
}
