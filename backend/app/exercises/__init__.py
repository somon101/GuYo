"""The one exercise-type registry every context (today: Lessons; see
app/routers/lessons.py) dispatches through instead of hardcoding its own
list. Adding a future exercise type -- for a future Practice/Test context,
or a new Lesson exercise -- is one new module here plus one new entry in
EXERCISE_TYPES; nothing that already works needs to change.

Each ExerciseType only carries `is_available` (source-of-truth for the
"can this exercise be included, given this exact word set" prerequisites
check -- see app/routers/lessons.py's create_lesson) -- round GENERATION
stays a plain function per module (`build_round`) rather than a forced
common signature, since each exercise's round genuinely has a different
shape (TrueOrFalseRoundOut vs ExerciseWordsOut vs BuildWordRoundOut vs
SpeakingWordRoundOut vs ListenWordRoundOut) and forcing one polymorphic
JSON shape across all of them would only make every consumer (Flutter
included) worse, not more "unified". What IS unified, and never
per-type: settings storage (ExerciseSettings, keyed by `key`), the
enabled/disabled gate (see `is_exercise_enabled` in common.py, applied
centrally in create_lesson -- no exercise type re-implements this), points
(`get_points`), and how an answer is scored/completes a lesson (the one
generic POST .../answers endpoint in lessons.py, unchanged by exercise_key).
"""

from dataclasses import dataclass
from typing import Callable

from sqlalchemy.orm import Session

from app.exercises import build_word, listen_word, matching, speaking_word, true_or_false
from app.models.user import User


@dataclass(frozen=True)
class ExerciseType:
    key: str
    is_available: Callable[[Session, User, int, list[int], int], bool]


EXERCISE_TYPES: dict[str, ExerciseType] = {
    true_or_false.KEY: ExerciseType(true_or_false.KEY, true_or_false.is_available),
    matching.KEY: ExerciseType(matching.KEY, matching.is_available),
    build_word.KEY: ExerciseType(build_word.KEY, build_word.is_available),
    speaking_word.KEY: ExerciseType(speaking_word.KEY, speaking_word.is_available),
    listen_word.KEY: ExerciseType(listen_word.KEY, listen_word.is_available),
}
