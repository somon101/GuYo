"""The server's own verdict on an answer.

Newer apps send what the learner actually did (`answer`) next to their
own right/wrong flag; the server judges that itself, so a tampered app
can't simply claim "correct". Older apps send no `answer` and keep their
own flag (see the minimum-version gate for closing that).

- true_or_false: {"shown": <translation on the card>, "choice": true|false}
- matching / listen_word: {"picked_word_id": <id of the card chosen>}
- build_word: {"text": <letters as assembled>}
- speaking_word: {"text": <recognized speech>}
"""

import re

from sqlalchemy.orm import Session

from app.core.content_language import primary_translation
from app.models.word import Word


def _words(s: str) -> list[str]:
    return [w for w in re.split(r"[^\w]+", s.lower()) if w and not w.isspace() and w != "_"]


def _levenshtein(a: str, b: str) -> int:
    prev = list(range(len(b) + 1))
    for i in range(1, len(a) + 1):
        cur = [i] + [0] * len(b)
        for j in range(1, len(b) + 1):
            cur[j] = min(cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + (a[i - 1] != b[j - 1]))
        prev = cur
    return prev[len(b)]


def _percent(a: str, b: str) -> int:
    if a == b:
        return 100
    longest = max(len(a), len(b))
    return max(0, min(100, round((1 - _levenshtein(a, b) / longest) * 100))) if longest else 0


def similarity_percent(recognized: str, target: str) -> int:
    """Same rule as the app: the best-matching run of as many words as the
    target has, by Levenshtein similarity (0-100)."""
    heard, wanted = _words(recognized), _words(target)
    if not heard or not wanted:
        return 0
    b = " ".join(wanted)
    best = _percent(" ".join(heard), b)
    for i in range(len(heard) - len(wanted) + 1):
        best = max(best, _percent(" ".join(heard[i : i + len(wanted)]), b))
    return best


def judge(db: Session, exercise_key: str, word: Word, answer: dict | None, timed_out: bool) -> bool | None:
    """True/False when the server can decide from `answer`, None when it
    can't (no answer sent, or an exercise it doesn't know) -- the caller
    then keeps the app's own flag."""
    if answer is None:
        return False if timed_out else None
    if timed_out:
        return False
    if exercise_key == "true_or_false":
        shown, choice = answer.get("shown"), answer.get("choice")
        if not isinstance(shown, str) or not isinstance(choice, bool):
            return None
        real = primary_translation(word)
        truth = real is not None and shown.strip() == real.text.strip()
        return choice == truth
    if exercise_key in ("matching", "listen_word"):
        picked = answer.get("picked_word_id")
        return picked == word.id if isinstance(picked, int) else None
    if exercise_key == "build_word":
        text = answer.get("text")
        if not isinstance(text, str):
            return None
        from app.exercises.build_word import get_build_word_settings

        _, _, case_sensitive = get_build_word_settings(db)
        return text == word.word if case_sensitive else text.lower() == word.word.lower()
    if exercise_key == "speaking_word":
        text = answer.get("text")
        if not isinstance(text, str):
            return None
        from app.exercises.speaking_word import get_match_threshold

        return similarity_percent(text, word.word) >= get_match_threshold(db)
    return None
