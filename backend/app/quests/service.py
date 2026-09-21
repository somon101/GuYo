"""Quest eligibility, round selection, and completion -- the one place a
word gets picked for a quest and the one place a quest's dual effect
(word reinforcement points + rating reward) gets applied. Entirely
separate from Lessons (never touches LessonWord/LessonExercise) and from
Achievements (never touches Achievement/UserAchievement); reuses only
what's explicitly shared: WordProgress scoring (app/exercises/common.py's
get_points, same as Lessons), and rating's own grant function
(app/rating/service.py's grant_rating_points).
"""

import random
from datetime import date

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.exercises.common import get_points, get_threshold
from app.models.quest import Quest, UserQuestWordDay
from app.models.user import User
from app.models.word import Word
from app.models.word_level import WordLevel
from app.models.word_progress import WordProgress
from app.quests.rounds import build_round_for_quest, is_quest_word_feasible
from app.rating import grant_rating_points


def _words_used_today(db: Session, user_id: int) -> set[int]:
    today = date.today()
    return {
        row[0]
        for row in db.query(UserQuestWordDay.word_id)
        .filter(UserQuestWordDay.user_id == user_id, UserQuestWordDay.used_date == today)
        .all()
    }


def candidate_words_for_quest(db: Session, user: User, quest: Quest, dictionary_id: int) -> list[Word]:
    """Every Word in this dictionary currently at the quest's target
    level for this user, excluding any word already used in ANY quest
    today -- the raw pool before checking whether a specific exercise_key
    can actually build a round for each one (see pick_quest_word)."""
    level = db.get(WordLevel, quest.word_level_id)
    if level is None:
        return []

    used_today = _words_used_today(db, user.id)

    query = (
        db.query(Word, WordProgress.score)
        .join(WordProgress, WordProgress.word_id == Word.id)
        .filter(
            Word.dictionary_id == dictionary_id,
            WordProgress.user_id == user.id,
            WordProgress.score >= level.min_points,
        )
    )
    if level.max_points is not None:
        query = query.filter(WordProgress.score <= level.max_points)

    return [word for word, _score in query.all() if word.id not in used_today]


def pick_quest_word(db: Session, user: User, quest: Quest, dictionary_id: int) -> Word | None:
    """One random eligible word for this quest that a round can actually
    be built for -- None if nothing qualifies right now (not enough
    progress at this level, or every eligible word was already used in a
    quest today)."""
    candidates = candidate_words_for_quest(db, user, quest, dictionary_id)
    random.shuffle(candidates)
    threshold = get_threshold(db)
    for word in candidates:
        if is_quest_word_feasible(db, user, dictionary_id, threshold, quest.exercise_key, word):
            return word
    return None


def is_quest_available(db: Session, user: User, quest: Quest, dictionary_id: int) -> bool:
    return pick_quest_word(db, user, quest, dictionary_id) is not None


def build_quest_round(db: Session, user: User, quest: Quest, dictionary_id: int, word: Word):
    threshold = get_threshold(db)
    return build_round_for_quest(db, user, dictionary_id, threshold, quest.exercise_key, word)


def complete_quest_attempt(db: Session, user: User, quest: Quest, word: Word, is_correct: bool) -> int:
    """Scores `word`'s WordProgress exactly like a Lesson answer would
    (same get_points(exercise_key) delta, same 0-100 clamp) and, only on
    success, grants the quest's rating reward and locks `word` out of
    every quest for the rest of today. Returns the word's new score.

    The daily lock is written inside its own SAVEPOINT (same pattern as
    app/rating/service.py's award_word_points_if_new) so a losing race
    against a concurrent request for the same (user, word) today just
    means this attempt's reward is skipped rather than a 500 -- the
    UNIQUE(user_id, word_id, used_date) constraint is what actually
    decides "already used today" at the database level."""
    correct_points, incorrect_points = get_points(db, quest.exercise_key)
    delta = correct_points if is_correct else -incorrect_points

    progress = db.query(WordProgress).filter(WordProgress.user_id == user.id, WordProgress.word_id == word.id).first()
    if progress is None:
        progress = WordProgress(user_id=user.id, word_id=word.id, score=0)
        db.add(progress)
        db.flush()

    progress.score = max(0, min(100, progress.score + delta))
    db.flush()

    if is_correct:
        try:
            with db.begin_nested():
                db.add(UserQuestWordDay(user_id=user.id, word_id=word.id, quest_id=quest.id, used_date=date.today()))
                db.flush()
        except IntegrityError:
            # Lost a race against a concurrent quest completion for the
            # same word today -- the word is locked either way, but this
            # request's own reward is skipped rather than double-granted.
            return progress.score

        grant_rating_points(db, user, quest.reward_points)

    return progress.score
