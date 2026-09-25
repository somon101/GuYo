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
from datetime import datetime, time, timezone

from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dates import DUSHANBE_TZ, dushanbe_today
from app.exercises.common import get_points, get_threshold
from app.models.quest import Quest, QuestWord, UserQuestWordDay
from app.priority.quests import order_candidates_by_priority
from app.models.user import User
from app.models.word import Word
from app.models.word_level import WordLevel
from app.models.word_progress import WordProgress
from app.quests.rounds import build_round_for_quest, is_quest_word_feasible
from app.rating import grant_rating_points


def _words_used_today(db: Session, user_id: int) -> set[int]:
    # Explicitly Asia/Dushanbe, never UTC or the device's own timezone --
    # GuYo's personal quests reset on Tajikistan's own clock, the same
    # moment for every user regardless of where their phone thinks it is.
    today = dushanbe_today()
    return {
        row[0]
        for row in db.query(UserQuestWordDay.word_id)
        .filter(UserQuestWordDay.user_id == user_id, UserQuestWordDay.used_date == today)
        .all()
    }


def quest_completions_today(db: Session, user_id: int) -> dict[int, int]:
    """How many words each quest has successfully consumed today, keyed by
    quest id. Counted straight from the UserQuestWordDay rows the quest
    flow already writes on every success -- there is no separate progress
    table, so this can never drift from what actually happened.

    Quests with nothing done today simply aren't in the returned map."""
    today = dushanbe_today()
    rows = (
        db.query(UserQuestWordDay.quest_id, func.count(UserQuestWordDay.id))
        .filter(UserQuestWordDay.user_id == user_id, UserQuestWordDay.used_date == today)
        .group_by(UserQuestWordDay.quest_id)
        .all()
    )
    return {quest_id: count for quest_id, count in rows}


def dushanbe_day_bounds_utc(day=None) -> tuple[datetime, datetime]:
    """The UTC instants one Asia/Dushanbe day starts and ends at -- what a
    timestamp column (UserWordPoints.awarded_at) has to be compared
    against to mean "today" on the same clock quests reset on."""
    day = day or dushanbe_today()
    start_local = datetime.combine(day, time.min, tzinfo=DUSHANBE_TZ)
    end_local = datetime.combine(day, time.max, tzinfo=DUSHANBE_TZ)
    return start_local.astimezone(timezone.utc), end_local.astimezone(timezone.utc)


def candidate_words_for_quest(db: Session, user: User, quest: Quest, dictionary_id: int) -> list[Word]:
    """Every Word in this dictionary currently at the quest's target
    level for this user, excluding any word already used in ANY quest
    today -- the raw pool before checking whether a specific exercise_key
    can actually build a round for each one (see pick_quest_word).

    A personal quest (quest.owner_user_id set -- see
    app/priority/quests_auto.py) has no target level at all; its
    candidates come from its own pinned QuestWord rows instead."""
    if quest.owner_user_id is not None:
        return _candidate_words_for_personal_quest(db, user, quest)

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


def _candidate_words_for_personal_quest(db: Session, user: User, quest: Quest) -> list[Word]:
    """A personal quest's own pinned words, minus whichever it has
    already consumed (on ANY day -- a personal quest's target is "finish
    each pinned word once, ever", not a daily repeat) and minus today's
    shared cross-quest lock (the same UserQuestWordDay rule that keeps an
    admin quest and a personal quest from ever double-using one word on
    the same day)."""
    pinned_ids = {word_id for (word_id,) in db.query(QuestWord.word_id).filter(QuestWord.quest_id == quest.id).all()}
    if not pinned_ids:
        return []
    already_done = {
        word_id
        for (word_id,) in db.query(UserQuestWordDay.word_id).filter(UserQuestWordDay.quest_id == quest.id).all()
    }
    remaining_ids = pinned_ids - already_done - _words_used_today(db, user.id)
    if not remaining_ids:
        return []
    return db.query(Word).filter(Word.id.in_(remaining_ids)).all()


def personal_quest_progress(db: Session, quest: Quest) -> tuple[int, int]:
    """(completed, target) for a personal quest -- completed counts EVERY
    UserQuestWordDay row for this quest_id, ever, not just today (see
    app/models/quest.py's own docstring on why a personal quest reuses
    daily_target/completed_today to mean "of its own pinned words", not
    "today's repeats")."""
    target = db.query(QuestWord).filter(QuestWord.quest_id == quest.id).count()
    completed = db.query(UserQuestWordDay).filter(UserQuestWordDay.quest_id == quest.id).count()
    return completed, target


def pick_quest_word(db: Session, user: User, quest: Quest, dictionary_id: int) -> Word | None:
    """One eligible word for this quest that a round can actually be
    built for -- None if nothing qualifies right now (not enough progress
    at this level, or every eligible word was already used in a quest
    today).

    Candidates are ordered High-priority first, then Medium, then
    everything else still shuffled (see app.priority.quests.
    order_candidates_by_priority) -- a word the user is currently
    struggling with is a more useful quest target than a random pick, but
    this never makes a quest impossible: with no High/Medium candidate at
    all, the first feasible word from the rest is picked exactly as
    before Priority existed."""
    candidates = order_candidates_by_priority(db, user.id, candidate_words_for_quest(db, user, quest, dictionary_id))
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
                db.add(UserQuestWordDay(user_id=user.id, word_id=word.id, quest_id=quest.id, used_date=dushanbe_today()))
                db.flush()
        except IntegrityError:
            # Lost a race against a concurrent quest completion for the
            # same word today -- the word is locked either way, but this
            # request's own reward is skipped rather than double-granted.
            return progress.score

        grant_rating_points(db, user, quest.reward_points)

    return progress.score
