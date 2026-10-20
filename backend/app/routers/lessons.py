"""Уроки ("Lessons"): the new primary progress system, replacing the old
flashcard "Изучил / Ещё раз буду изучать" flow (app/routers/learning.py,
now unused by the app but left in place -- see the migration notes).

A Lesson is a fixed, <=15-word set the user picked (randomly or by hand)
for one dictionary, plus whichever exercise types turned out to be
available for that exact set (see app.exercises.EXERCISE_TYPES). Nothing
here duplicates Word -- every LessonWord is just a word_id reference, the
same principle as every other exercise in this codebase.

Answers are recorded (WordAttempt); when a pass ends, the words its answers
prove become learned (app/learning/mastery.py). Once every word in a lesson
is learned, the lesson is complete and a new one can be created. This is
the ONE place "is this word learned" is decided.

This router is the ONE current caller of app.exercises (context=Lesson).
Everything about a specific exercise type -- its own prerequisites, round
shape, generation -- lives in its own app/exercises/<key>.py module; this
file only does Lesson-specific bookkeeping (which lesson, which words,
whether it's complete) and dispatches to that module by exercise_key.
"""
import random

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.achievements.conditions import streak_days_count
from app.exercises.verify import judge
from app.analytics.history import log_event
from app.core.content_language import primary_translation
from app.core.dates import utc_now
from app.core.deps import get_current_admin, get_current_user, require_current_app
from app.core.storage import url_for_key
from app.database import get_db
from app.achievements import check_and_grant_achievements, record_activity
from app.rating import award_word_points_if_new
from app.exercises import EXERCISE_TYPES, build_word, listen_word, matching, speaking_word, true_or_false
from app.exercises.common import (
    fill_word_progress,
    get_eligible_words,
    is_exercise_enabled,
    lesson_words_not_learned,
)
from app.models.dictionary import Dictionary
from app.models.learning_settings import LearningSettings
from app.models.lesson import Lesson, LessonExercise, LessonWord
from app.models.user import User
from app.models.word import Word, WordTopic
from app.memory import recall_probability, secured_word_ids
from app.learning.mastery import apply_pass, learned_ids, progress_row
from app.word_levels import memory_levels_for
from app.models.word_attempt import WordAttempt
from app.models.word_progress import WordProgress
from app.premium import LessonLimitReached, check_lesson_quota
from app.priority.background_prep import mark_for_prep
from app.routers.words import word_to_out
from app.word_attempts import record_word_attempt

from app.schemas.exercise import BuildWordRoundOut, ExerciseWordsOut, TrueOrFalseRoundOut
from app.schemas.lesson import (
    CreateLessonIn,
    LearningSettingsIn,
    LearningSettingsOut,
    LessonCandidateWordsOut,
    LessonPassStatsOut,
    LessonListOut,
    LessonOut,
    LessonSummaryOut,
    LessonWordOut,
    PassExerciseStatOut,
    PassWordStatOut,
    ListenWordRoundOut,
    SpeakingWordRoundOut,
    SubmitAnswerIn,
    SubmitAnswerOut,
)

router = APIRouter(tags=["lessons"])


# What the `score` fields still sent to installed apps mean: learned.
LEARNED = 100


def _get_published_dictionary_or_404(db: Session, dictionary_id: int) -> Dictionary:
    dictionary = db.get(Dictionary, dictionary_id)
    if dictionary is None or not dictionary.is_published:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")
    return dictionary


def _get_active_lesson(db: Session, user_id: int, dictionary_id: int) -> Lesson | None:
    return (
        db.query(Lesson)
        .filter(Lesson.user_id == user_id, Lesson.dictionary_id == dictionary_id, Lesson.is_completed.is_(False))
        .first()
    )


def _get_owned_lesson_or_404(db: Session, user_id: int, lesson_id: int) -> Lesson:
    lesson = db.get(Lesson, lesson_id)
    if lesson is None or lesson.user_id != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Lesson not found")
    return lesson


def _require_lesson_exercise(db: Session, lesson_id: int, exercise_key: str) -> None:
    exists = (
        db.query(LessonExercise)
        .filter(LessonExercise.lesson_id == lesson_id, LessonExercise.exercise_key == exercise_key)
        .first()
        is not None
    )
    if not exists:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="This exercise isn't part of this lesson"
        )


def _lesson_to_out(db: Session, lesson: Lesson) -> LessonOut:
    lesson_words = db.query(LessonWord).filter(LessonWord.lesson_id == lesson.id).order_by(LessonWord.id).all()
    word_ids = [lw.word_id for lw in lesson_words]
    learned = learned_ids(db, lesson.user_id, word_ids)

    levels = memory_levels_for(db, lesson.user_id, word_ids)
    words_out = []
    for lw in lesson_words:
        w = lw.word
        # No points any more: `score` only says learned (100) or not (0); the
        # level is the memory model's (app/word_levels/service.py).
        score = 100 if lw.word_id in learned else 0
        primary = primary_translation(w)
        level = levels.get(lw.word_id)
        words_out.append(
            LessonWordOut(
                word_id=w.id,
                word=w.word,
                translation=primary.text if primary else None,
                score=score,
                is_learned=lw.word_id in learned,
                word_level_id=level.id if level else None,
                word_level_name=level.name if level else None,
                transcription=w.transcription,
                word_audio_url=url_for_key(w.word_audio_key),
                translation_audio_url=url_for_key(primary.audio_key) if primary else None,
                image_url=url_for_key(w.image_key),
            )
        )

    exercise_keys = [
        le.exercise_key
        for le in db.query(LessonExercise).filter(LessonExercise.lesson_id == lesson.id).order_by(LessonExercise.id).all()
    ]

    # Mini-phrases are part of the lesson until it's completed: every pass
    # ends with them (see app/mini_phrases).
    mini_phrases = []
    if not lesson.is_completed:
        from app.mini_phrases import lesson_mini_phrases_out

        owner = db.get(User, lesson.user_id)
        if owner is not None:
            mini_phrases = lesson_mini_phrases_out(db, owner, lesson)

    return LessonOut(
        id=lesson.id,
        dictionary_id=lesson.dictionary_id,
        number=lesson.number,
        is_completed=lesson.is_completed,
        exercise_keys=exercise_keys,
        words=words_out,
        mini_phrases=mini_phrases,
    )


def _lesson_to_summary(db: Session, lesson: Lesson) -> LessonSummaryOut:
    """One row of the full lesson history -- see GET
    /dictionaries/{id}/lessons. Deliberately lighter than `_lesson_to_out`:
    just the counts the chain screen needs to render one link, not every
    word's own text/translation/score."""
    word_ids = [row[0] for row in db.query(LessonWord.word_id).filter(LessonWord.lesson_id == lesson.id).all()]
    learned_count = len(secured_word_ids(db, lesson.user_id, word_ids)) if word_ids else 0
    return LessonSummaryOut(
        id=lesson.id,
        number=lesson.number,
        is_completed=lesson.is_completed,
        word_count=len(word_ids),
        learned_count=learned_count,
    )


def _check_and_apply_lesson_completion(db: Session, lesson: Lesson) -> bool:
    """A lesson is complete exactly when ALL its words are learned
    (app/learning/mastery.py), never "most of them"."""
    if lesson.is_completed:
        return True
    word_ids = [row[0] for row in db.query(LessonWord.word_id).filter(LessonWord.lesson_id == lesson.id).all()]
    if not word_ids:
        return False
    if len(secured_word_ids(db, lesson.user_id, word_ids)) == len(word_ids):
        lesson.is_completed = True
        lesson.completed_at = func.now()
        log_event(db, lesson.user_id, "lesson_completed", lesson_id=lesson.id,
                  data={"number": lesson.number, "adaptive": lesson.is_adaptive})
        return True
    return False


# --- Lesson lifecycle -----------------------------------------------------


@router.get("/dictionaries/{dictionary_id}/lesson-candidate-words", response_model=LessonCandidateWordsOut)
def get_lesson_candidate_words(
    dictionary_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """The pool a new lesson's word picker draws from -- every word in this
    dictionary the user hasn't already learned. Used for BOTH selection
    modes: the random picker shows `available_count` as the usable max
    (alongside the fixed 1-15 cap), and the manual picker lists `words`
    (grouped by category client-side, same as the old "Мои слова"
    screen) with a checkbox each."""
    _get_published_dictionary_or_404(db, dictionary_id)
    words = get_eligible_words(db, user.id, dictionary_id)
    out = [word_to_out(w) for w in words]
    # So the picker's word cards carry the same score/level every other
    # word list shows -- the shared helper, never a second classification.
    fill_word_progress(db, user.id, out, [w.id for w in words])
    return LessonCandidateWordsOut(
        dictionary_id=dictionary_id, available_count=len(words), words=out, max_words=max_lesson_words(db)
    )


@router.get("/lessons/active", response_model=LessonOut)
def get_active_lesson(
    dictionary_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    _get_published_dictionary_or_404(db, dictionary_id)
    lesson = _get_active_lesson(db, user.id, dictionary_id)
    if lesson is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No active lesson")
    return _lesson_to_out(db, lesson)


@router.get("/dictionaries/{dictionary_id}/lessons", response_model=LessonListOut)
def list_lessons(
    dictionary_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """The full, permanent lesson history for this (user, dictionary) --
    every lesson ever created, oldest first, each with its current status.
    Lessons are never deleted (see Lesson's docstring), so this is the
    "Уроки" chain screen's one source of truth: unlike get_active_lesson,
    an empty list or an all-completed history is a normal, valid response,
    never a 404."""
    _get_published_dictionary_or_404(db, dictionary_id)
    lessons = (
        db.query(Lesson)
        .filter(Lesson.user_id == user.id, Lesson.dictionary_id == dictionary_id)
        .order_by(Lesson.number)
        .all()
    )
    return LessonListOut(
        dictionary_id=dictionary_id,
        lessons=[_lesson_to_summary(db, lesson) for lesson in lessons],
    )


@router.get("/lessons/{lesson_id}", response_model=LessonOut)
def get_lesson(
    lesson_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    lesson = _get_owned_lesson_or_404(db, user.id, lesson_id)
    return _lesson_to_out(db, lesson)


@router.post("/lessons/{lesson_id}/pass", response_model=LessonOut)
def start_lesson_pass(
    lesson_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    _app: None = Depends(require_current_app),
):
    """Starts one pass through this lesson's exercises: freezes the words
    still below their level RIGHT NOW as the set every exercise in this
    pass draws from (Lesson.pass_word_ids, read by lesson_words_pending).
    A word that reaches its level in exercise 1 therefore still goes
    through exercises 2, 3, ... of the same pass; only the next pass
    leaves it out. The app calls this at the start of every pass --
    first run and each "Повторить урок" alike. Changes no score."""
    lesson = _get_owned_lesson_or_404(db, user.id, lesson_id)
    lesson.pass_word_ids = [w.id for w in lesson_words_not_learned(db, lesson)]
    # The baseline the end-of-pass statistics are measured against.
    lesson.pass_started_at = utc_now()
    lesson.pass_start_scores = {str(word_id): score for word_id, score in _word_scores(db, user.id, lesson).items()}
    # Any earlier pass left unfinished is dropped -- its answers never count.
    lesson.pass_pending_scores = None
    db.commit()
    db.refresh(lesson)
    return _lesson_to_out(db, lesson)


def _word_scores(db: Session, user_id: int, lesson: Lesson) -> dict[int, int]:
    """Every word of this lesson -> 100 when learned, else 0 (what the pass
    statistics compare before and after: did the word become learned)."""
    word_ids = [lw.word_id for lw in lesson.words]
    learned = learned_ids(db, user_id, word_ids)
    return {word_id: (100 if word_id in learned else 0) for word_id in word_ids}


@router.get("/lessons/{lesson_id}/pass/stats", response_model=LessonPassStatsOut)
def get_lesson_pass_stats(
    lesson_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """How the current pass went: answers, accuracy, a per-exercise
    breakdown, and each word's score before and after. Counts only answers
    given in THIS lesson (WordAttempt.lesson_id) since the pass started;
    nothing here changes any score. A lesson no pass was ever started for
    reports every answer ever given in it, measured from zero."""
    lesson = _get_owned_lesson_or_404(db, user.id, lesson_id)
    return _pass_stats(db, user, lesson)


def _pass_stats(db: Session, user: User, lesson: Lesson) -> LessonPassStatsOut:

    attempts_q = db.query(WordAttempt).filter(WordAttempt.user_id == user.id, WordAttempt.lesson_id == lesson.id)
    if lesson.pass_started_at is not None:
        attempts_q = attempts_q.filter(WordAttempt.created_at >= lesson.pass_started_at)
    attempts = attempts_q.all()

    per_exercise: dict[str, list[int]] = {}
    for attempt in attempts:
        counts = per_exercise.setdefault(attempt.exercise_key, [0, 0])
        counts[1] += 1
        if attempt.is_correct:
            counts[0] += 1
    order = {key: i for i, key in enumerate(EXERCISE_TYPES)}
    exercises = [
        PassExerciseStatOut(exercise_key=key, correct=c, total=t)
        for key, (c, t) in sorted(per_exercise.items(), key=lambda kv: order.get(kv[0], len(order)))
    ]

    before = {int(k): v for k, v in (lesson.pass_start_scores or {}).items()}
    after = _word_scores(db, user.id, lesson)
    frozen = set(lesson.pass_word_ids) if lesson.pass_word_ids is not None else None
    words = []
    for lw in lesson.words:
        if frozen is not None and lw.word_id not in frozen:
            continue  # not part of this pass
        was, now = before.get(lw.word_id, 0), after.get(lw.word_id, 0)
        words.append(
            PassWordStatOut(
                word_id=lw.word_id,
                word=lw.word.word,
                score_before=was,
                score_after=now,
                gained=0,  # no points any more: became_learned says what changed
                became_learned=was < LEARNED <= now,
            )
        )

    total = len(attempts)
    correct = sum(1 for a in attempts if a.is_correct)
    duration = 0
    if lesson.pass_started_at is not None:
        last = max((a.created_at for a in attempts), default=None)
        end = last if last is not None else lesson.pass_started_at
        duration = max(0, int((end - lesson.pass_started_at).total_seconds()))
    return LessonPassStatsOut(
        started_at=lesson.pass_started_at,
        duration_seconds=duration,
        total_answers=total,
        correct_answers=correct,
        wrong_answers=total - correct,
        accuracy=round(correct * 100 / total) if total else 0,
        exercises=exercises,
        words=words,
        score_gained=sum(w.gained for w in words),
        newly_learned=sum(1 for w in words if w.became_learned),
    )


@router.post("/lessons", response_model=LessonOut, status_code=status.HTTP_201_CREATED)
def create_lesson(
    payload: CreateLessonIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Freezes a specific set of word_ids (<=15, chosen randomly or by
    hand -- never both) into a new Lesson, then decides once which
    exercise types are available for that exact set (app.exercises.
    EXERCISE_TYPES, gated first by each exercise_key's own enabled/
    disabled admin setting) and persists that too (LessonExercise) --
    never recomputed afterwards. Blocked while the current lesson for this
    (user, dictionary) isn't complete yet, enforced here AND at the
    database level (see Lesson's partial unique index) against a race
    between two requests.

    Also counts against the user's daily/weekly lesson limit (see
    app/premium/service.py) -- a 429 with the reason and when it resets.
    Checked after the active-lesson rule, so a user with an unfinished
    lesson is told to finish it rather than about a limit."""
    dictionary = _get_published_dictionary_or_404(db, payload.dictionary_id)

    cap = max_lesson_words(db)
    asked = len(payload.word_ids) if payload.word_ids is not None else (payload.random_count or 0)
    if asked > cap:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"В уроке может быть не больше {cap} слов",
        )

    if _get_active_lesson(db, user.id, dictionary.id) is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Текущий урок ещё не завершён -- сначала пройдите его до конца",
        )

    try:
        check_lesson_quota(db, user)
    except LessonLimitReached as e:
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=str(e))

    eligible_words = get_eligible_words(db, user.id, dictionary.id)
    eligible_ids = {w.id for w in eligible_words}
    # With one or two words most exercises can't run, so a word can't reach
    # "learned" in a pass even with no mistakes -- a lesson takes at least
    # MIN_LESSON_WORDS (or every word left, when fewer remain).
    min_words = min(MIN_LESSON_WORDS, len(eligible_ids))
    if payload.word_ids is not None and len(set(payload.word_ids)) < min_words:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Выберите минимум {min_words} слова для урока",
        )

    if payload.word_ids is not None:
        if len(set(payload.word_ids)) != len(payload.word_ids):
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Слово выбрано дважды")
        invalid = [wid for wid in payload.word_ids if wid not in eligible_ids]
        if invalid:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Эти слова недоступны для нового урока (уже изучены или не из этого словаря): {invalid}",
            )
        selected_ids = list(payload.word_ids)
    else:
        if not eligible_ids:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Нет доступных слов для нового урока")
        count = min(max(payload.random_count, min_words), len(eligible_ids))
        selected_ids = [w.id for w in prioritized_words(db, user, eligible_words, count=count, dictionary=dictionary)[:count]]

    lesson = build_lesson(db, user, dictionary, selected_ids)
    db.commit()
    db.refresh(lesson)
    return _lesson_to_out(db, lesson)


MIN_LESSON_WORDS = 4
# An answer arriving faster than this cannot have been read, let alone thought
# about: it is counted as wrong (see submit_answer). Below simple human reaction
# time, so an honest quick tap on a word the user knows is never touched.
MIN_ANSWER_MS = 300
# And a whole pass whose SLOWEST answer beat this is a script, not a learner:
# its words count, its rating points do not (see _pass_too_fast).
IMPLAUSIBLE_PASS_MS = 1000


def prioritized_words(
    db: Session, user: User, words: list[Word], *, count: int | None = None, dictionary: Dictionary | None = None
) -> list[Word]:
    """The order a random lesson draws from: words in the user's own topics
    first, then the rest; within each, the most important first; words of
    equal standing shuffled, so two lessons are never the same list."""
    topics = set(user.learning_topics or [])
    # Words already started that the user is forgetting come first.
    due: dict[int, float] = {}
    if words:
        for progress in db.query(WordProgress).filter(
            WordProgress.user_id == user.id, WordProgress.word_id.in_([w.id for w in words])
        ):
            r = recall_probability(progress)
            if r is not None:
                due[progress.word_id] = r
    in_topic: set[int] = set()
    if topics and words:
        in_topic = {
            word_id
            for (word_id,) in db.query(WordTopic.word_id)
            .filter(WordTopic.word_id.in_([w.id for w in words]), WordTopic.topic.in_(topics))
            .all()
        }
    ordered = sorted(
        words,
        key=lambda w: (w.id not in due, due.get(w.id, 1.0), w.id not in in_topic, -w.importance, random.random()),
    )
    if not count or dictionary is None:
        return ordered
    # About a third of the slots after the words being forgotten go to the
    # words that open the most phrases right away (app/priority/
    # phrase_unlock.py) -- the learner starts talking sooner; the rest keep
    # the goal/importance order above.
    from app.priority.phrase_unlock import PHRASE_UNLOCK_SHARE, phrase_unlock_scores

    forgotten = [w for w in ordered if w.id in due][:count]
    free = count - len(forgotten)
    unlock_slots = int(free * PHRASE_UNLOCK_SHARE + 0.5) if free > 0 else 0
    if unlock_slots <= 0:
        return ordered
    scores = phrase_unlock_scores(db, user, dictionary)
    openers = sorted(
        (w for w in ordered if w.id not in due and scores.get(w.id, 0) > 0),
        key=lambda w: (-scores[w.id], w.id not in in_topic, -w.importance),
    )[:unlock_slots]
    taken = {w.id for w in forgotten} | {w.id for w in openers}
    return forgotten + openers + [w for w in ordered if w.id not in taken]


def build_lesson(
    db: Session, user: User, dictionary: Dictionary, selected_ids: list[int], *, is_adaptive: bool = False
) -> Lesson:
    """The actual Lesson/LessonWord/LessonExercise construction, shared by
    the HTTP endpoint above and app.priority.lessons's auto-created
    adaptive lessons -- an adaptive lesson goes through the EXACT SAME
    freeze-the-word-set-then-decide-exercises steps, just with `is_adaptive
    =True` and a caller-chosen word set instead of one a user picked.
    Does NOT commit -- the caller owns the transaction, so
    app.priority.lessons can create the lesson in the same transaction as
    the attempt that triggered it."""
    last_number = (
        db.query(func.max(Lesson.number))
        .filter(Lesson.user_id == user.id, Lesson.dictionary_id == dictionary.id)
        .scalar()
        or 0
    )

    lesson = Lesson(user_id=user.id, dictionary_id=dictionary.id, number=last_number + 1, is_adaptive=is_adaptive)
    db.add(lesson)
    db.flush()

    for word_id in selected_ids:
        db.add(LessonWord(lesson_id=lesson.id, word_id=word_id))

    for exercise_key, exercise_type in EXERCISE_TYPES.items():
        if not is_exercise_enabled(db, exercise_key):
            continue
        if exercise_type.is_available(db, user, dictionary.id, selected_ids):
            db.add(LessonExercise(lesson_id=lesson.id, exercise_key=exercise_key))

    # The mini-phrases this lesson's words open (with what's already known),
    # frozen with the lesson like its words -- see app/mini_phrases.
    from app.mini_phrases import attach_to_lesson

    attach_to_lesson(db, user, lesson, list(selected_ids))

    log_event(db, user.id, "lesson_created", lesson_id=lesson.id,
              data={"number": lesson.number, "adaptive": is_adaptive, "words": len(selected_ids)})
    db.flush()
    return lesson


# --- Lesson exercise rounds -------------------------------------------------
# Each endpoint here is a thin Lesson-specific wrapper: look up the lesson,
# confirm this exercise_key was actually decided available for it, then
# hand off to that exercise type's own build_round (app/exercises/<key>.py)
# for the actual round shape/logic.


def _only_words(lesson: Lesson, word_ids: str | None) -> None:
    """`word_ids=1,2,3`: the round covers only these words of the pass --
    the app re-asks words answered wrong, at the end of the same pass, until
    they are right. Nothing is stored."""
    if word_ids:
        lesson.only_word_ids = {int(x) for x in word_ids.split(",") if x.strip().isdigit()}


@router.get("/lessons/{lesson_id}/exercises/true-or-false", response_model=TrueOrFalseRoundOut)
def get_lesson_true_or_false_round(
    lesson_id: int,
    word_ids: str | None = Query(default=None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    lesson = _get_owned_lesson_or_404(db, user.id, lesson_id)
    _only_words(lesson, word_ids)
    _require_lesson_exercise(db, lesson.id, true_or_false.KEY)
    return true_or_false.build_round(db, lesson)


@router.get("/lessons/{lesson_id}/exercises/matching", response_model=ExerciseWordsOut)
def get_lesson_matching_round(
    lesson_id: int,
    word_ids: str | None = Query(default=None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    lesson = _get_owned_lesson_or_404(db, user.id, lesson_id)
    _only_words(lesson, word_ids)
    _require_lesson_exercise(db, lesson.id, matching.KEY)
    return matching.build_round(db, lesson)


@router.get("/lessons/{lesson_id}/exercises/build-word", response_model=BuildWordRoundOut)
def get_lesson_build_word_round(
    lesson_id: int,
    word_ids: str | None = Query(default=None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    lesson = _get_owned_lesson_or_404(db, user.id, lesson_id)
    _only_words(lesson, word_ids)
    _require_lesson_exercise(db, lesson.id, build_word.KEY)
    return build_word.build_round(db, lesson)


@router.get("/lessons/{lesson_id}/exercises/speaking-word", response_model=SpeakingWordRoundOut)
def get_lesson_speaking_word_round(
    lesson_id: int,
    word_ids: str | None = Query(default=None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    lesson = _get_owned_lesson_or_404(db, user.id, lesson_id)
    _only_words(lesson, word_ids)
    _require_lesson_exercise(db, lesson.id, speaking_word.KEY)
    return speaking_word.build_round(db, lesson)


@router.get("/lessons/{lesson_id}/exercises/listen-word", response_model=ListenWordRoundOut)
def get_lesson_listen_word_round(
    lesson_id: int,
    word_ids: str | None = Query(default=None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    lesson = _get_owned_lesson_or_404(db, user.id, lesson_id)
    _only_words(lesson, word_ids)
    _require_lesson_exercise(db, lesson.id, listen_word.KEY)
    return listen_word.build_round(db, lesson)


def _pass_too_fast(db: Session, user_id: int, lesson: Lesson) -> bool:
    """True when EVERY answer of the current pass came back faster than a person
    could read it (see MIN_ANSWER_MS for the single-answer rule). Fewer than five
    answers is never judged: there is not enough to tell speed from luck."""
    query = db.query(WordAttempt.duration_ms).filter(
        WordAttempt.user_id == user_id, WordAttempt.lesson_id == lesson.id
    )
    if lesson.pass_started_at is not None:
        query = query.filter(WordAttempt.created_at >= lesson.pass_started_at)
    durations = [d for (d,) in query.all() if d is not None]
    if len(durations) < 5:
        return False
    return max(durations) < IMPLAUSIBLE_PASS_MS


def _hold_answer_for_pass(db: Session, user: User, lesson: Lesson, exercise_key: str, payload):
    """A deferred answer: only recorded. Whether its word became learned is
    decided when the pass is finished (finish_lesson_pass) -- nothing counts
    from a pass the user doesn't finish."""
    progress_row(db, user.id, payload.word_id)
    record_word_attempt(
        db,
        user_id=user.id,
        word_id=payload.word_id,
        exercise_key=exercise_key,
        is_correct=payload.is_correct,
        lesson_id=lesson.id,
        duration_ms=payload.duration_ms,
        timed_out=payload.timed_out,
        given_answer=payload.given_answer,
        phrase_id=payload.phrase_id,
        mini_phrase_id=payload.mini_phrase_id,
    )
    db.commit()
    learned = bool(learned_ids(db, user.id, [payload.word_id]))
    return SubmitAnswerOut(
        word_id=payload.word_id,
        score=100 if learned else 0,
        is_learned=learned,
        lesson_completed=False,
        points_awarded=0,
    )


@router.post("/lessons/{lesson_id}/pass/finish", response_model=LessonOut)
def finish_lesson_pass(
    lesson_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    _app: None = Depends(require_current_app),
):
    """The pass was played to the end: the words it proved become learned,
    and everything that follows happens here."""
    lesson = _get_owned_lesson_or_404(db, user.id, lesson_id)
    # A lesson (or adaptive lesson, or a repeat) played to the end lights
    # today's streak day.
    lit_now = record_activity(db, user)
    db.commit()
    # The words this pass proved become learned now (app/learning/mastery.py);
    # everything that follows from that happens here -- rating points,
    # achievements, lesson completion. Finishing twice changes nothing more.
    newly_learned = apply_pass(db, user.id, lesson)
    lesson.pass_pending_scores = None
    lesson_completed = _check_and_apply_lesson_completion(db, lesson)
    if lesson_completed and not lesson.completed_by_pass:
        # Finishing the pass is the one genuine "played to the end" signal --
        # the only place completed_by_pass is set, so the "lessons_completed"
        # achievement rewards a real playthrough.
        lesson.completed_by_pass = True
        db.flush()
        check_and_grant_achievements(db, user, "lessons_completed")
    # Auto lesson/quest are built quietly later (app/priority/background_prep.py).
    mark_for_prep(db, user, lesson.dictionary_id)
    if newly_learned:
        check_and_grant_achievements(db, user, "words_learned")
        # A pass where every single answer came back faster than a person can
        # read earns no rating points: the words still count, so an honest
        # fast player loses nothing, while a script gains no rank.
        if not _pass_too_fast(db, user.id, lesson):
            for word_id in newly_learned:
                award_word_points_if_new(db, user, word_id)
    # The lesson's mini-phrases were gone through on this pass: they're
    # open now (Практика) and never attached to another lesson.
    from app.mini_phrases import mark_done
    from app.models.mini_phrase import LessonMiniPhrase

    for (mini_phrase_id,) in db.query(LessonMiniPhrase.mini_phrase_id).filter(LessonMiniPhrase.lesson_id == lesson.id):
        mark_done(db, user.id, mini_phrase_id)
    db.flush()
    check_and_grant_achievements(db, user, "mini_phrases_done")
    db.commit()
    db.refresh(lesson)
    out = _lesson_to_out(db, lesson)
    out.streak_lit_now = lit_now
    out.streak_days = streak_days_count(db, user)
    # The results screen's numbers in the same response: the app shows the
    # results after ONE round trip instead of three.
    out.pass_stats = _pass_stats(db, user, lesson)
    return out


@router.post("/lessons/{lesson_id}/exercises/{exercise_key}/answers", response_model=SubmitAnswerOut)
def submit_answer(
    lesson_id: int,
    exercise_key: str,
    payload: SubmitAnswerIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    _app: None = Depends(require_current_app),
):
    """One answer in a lesson. It is recorded (the memory model learns from
    every answer); whether its word is learned is judged by the pass rule
    (app/learning/mastery.py). `word_id` must belong to THIS lesson."""
    lesson = _get_owned_lesson_or_404(db, user.id, lesson_id)
    _require_lesson_exercise(db, lesson.id, exercise_key)

    in_lesson = (
        db.query(LessonWord).filter(LessonWord.lesson_id == lesson.id, LessonWord.word_id == payload.word_id).first()
        is not None
    )
    if not in_lesson:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Word not in this lesson")

    # The server's own verdict when the app says what was actually done.
    verdict = judge(db, exercise_key, db.get(Word, payload.word_id), payload.answer, payload.timed_out)
    if verdict is not None:
        payload.is_correct = verdict

    # --- Anti-farming --------------------------------------------------------
    # An answer that comes back faster than anyone could read the options is not
    # an answer: it counts as WRONG (like a timeout) rather than being ignored,
    # so spamming gains nothing. A single quick tap is left alone -- knowing the
    # word and tapping it at once is normal.
    if not payload.timed_out and payload.duration_ms is not None and payload.duration_ms < MIN_ANSWER_MS:
        payload.is_correct = False

    if payload.deferred:
        return _hold_answer_for_pass(db, user, lesson, exercise_key, payload)

    # An older app scores answer by answer: the answer is recorded and its
    # word judged right away by the same rule a finished pass uses.
    progress = progress_row(db, user.id, payload.word_id)
    record_word_attempt(
        db,
        user_id=user.id,
        word_id=payload.word_id,
        exercise_key=exercise_key,
        is_correct=payload.is_correct,
        lesson_id=lesson.id,
        duration_ms=payload.duration_ms,
        timed_out=payload.timed_out,
        given_answer=payload.given_answer,
        phrase_id=payload.phrase_id,
        mini_phrase_id=payload.mini_phrase_id,
    )
    newly_learned = apply_pass(db, user.id, lesson, [payload.word_id])
    lesson_completed = _check_and_apply_lesson_completion(db, lesson)
    if lesson_completed:
        db.flush()
    is_learned = progress.mastered_at is not None
    mark_for_prep(db, user, lesson.dictionary_id)
    points_awarded = 0
    if newly_learned:
        check_and_grant_achievements(db, user, "words_learned")
        points_awarded = award_word_points_if_new(db, user, payload.word_id)

    db.commit()
    return SubmitAnswerOut(
        word_id=payload.word_id,
        score=100 if is_learned else 0,
        is_learned=is_learned,
        lesson_completed=lesson_completed,
        points_awarded=points_awarded,
    )


# --- Admin: learning settings --------------------------------------


def max_lesson_words(db: Session) -> int:
    """The most words one lesson may have (Admin Web -> Упражнения)."""
    settings = db.get(LearningSettings, 1)
    return settings.max_lesson_words if settings is not None and settings.max_lesson_words else 15


@router.get("/learning-settings", response_model=LearningSettingsOut)
def get_learning_settings(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    return LearningSettingsOut(max_lesson_words=max_lesson_words(db))


@router.put("/learning-settings", response_model=LearningSettingsOut)
def set_learning_settings(
    payload: LearningSettingsIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    settings = db.get(LearningSettings, 1)
    if settings is None:
        settings = LearningSettings(id=1)
        db.add(settings)
    if payload.max_lesson_words is not None:
        settings.max_lesson_words = payload.max_lesson_words
    db.commit()
    return LearningSettingsOut(max_lesson_words=settings.max_lesson_words)
