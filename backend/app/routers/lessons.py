"""Уроки ("Lessons"): the new primary progress system, replacing the old
flashcard "Изучил / Ещё раз буду изучать" flow (app/routers/learning.py,
now unused by the app but left in place -- see the migration notes).

A Lesson is a fixed, <=15-word set the user picked (randomly or by hand)
for one dictionary, plus whichever exercise types turned out to be
available for that exact set (see EXERCISE_AVAILABILITY below). Nothing
here duplicates Word -- every LessonWord is just a word_id reference, the
same principle as every other exercise in this codebase.

Each answer a user submits to one of this lesson's exercises moves that
specific word_id's WordProgress.score (0-100, see app/models/
word_progress.py) by that exercise's admin-configured points. Once a
word's score reaches the admin's configured threshold (see
app/models/learning_settings.py), it counts as learned; once every word
in a lesson does, the lesson itself is complete and a new one can be
created. This is the ONE place "is this word learned" is decided now --
nothing here reads or writes the old LearnedWord table.
"""
import random

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin, get_current_user
from app.core.storage import url_for_key
from app.database import get_db
from app.models.dictionary import Dictionary
from app.models.exercise import ExerciseSettings
from app.models.learning_settings import LearningSettings
from app.models.lesson import Lesson, LessonExercise, LessonWord
from app.models.user import User
from app.models.word import Word
from app.models.word_progress import WordProgress
from app.routers.exercises import (
    BUILD_WORD_KEY,
    MATCHING_KEY,
    TRUE_OR_FALSE_KEY,
    _build_word_item,
    _get_build_word_settings,
)
from app.routers.words import word_to_out
from app.schemas.exercise import BuildWordRoundOut, ExerciseWordsOut, TrueOrFalseItemOut, TrueOrFalseRoundOut
from app.schemas.lesson import (
    CreateLessonIn,
    LearningSettingsIn,
    LearningSettingsOut,
    LessonCandidateWordsOut,
    LessonListOut,
    LessonOut,
    LessonSummaryOut,
    LessonWordOut,
    SubmitAnswerIn,
    SubmitAnswerOut,
)

router = APIRouter(tags=["lessons"])

DEFAULT_THRESHOLD = 60
# (correct, incorrect) points, only used when an admin hasn't configured a
# given exercise_key's own values yet -- purely illustrative numbers from
# the spec, not meant to be load-bearing once Admin Web has real settings.
DEFAULT_POINTS: dict[str, tuple[int, int]] = {
    MATCHING_KEY: (20, 10),
    TRUE_OR_FALSE_KEY: (10, 5),
    BUILD_WORD_KEY: (30, 15),
}


def _get_published_dictionary_or_404(db: Session, dictionary_id: int) -> Dictionary:
    dictionary = db.get(Dictionary, dictionary_id)
    if dictionary is None or not dictionary.is_published:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")
    return dictionary


def _get_threshold(db: Session) -> int:
    settings = db.get(LearningSettings, 1)
    return settings.threshold_score if settings is not None else DEFAULT_THRESHOLD


def _get_points(db: Session, exercise_key: str) -> tuple[int, int]:
    """(correct_points, incorrect_points) -- incorrect_points is always a
    positive "how much to subtract" number, matching how Admin Web presents
    it (e.g. "-10" meaning score decreases by 10)."""
    settings = db.query(ExerciseSettings).filter(ExerciseSettings.exercise_key == exercise_key).first()
    default_correct, default_incorrect = DEFAULT_POINTS.get(exercise_key, (10, 5))
    correct = settings.correct_points if settings and settings.correct_points is not None else default_correct
    incorrect = settings.incorrect_points if settings and settings.incorrect_points is not None else default_incorrect
    return correct, incorrect


def _get_eligible_words(db: Session, user_id: int, dictionary_id: int, threshold: int) -> list[Word]:
    """Every Word in this dictionary NOT already learned (WordProgress.score
    >= threshold) -- the one pool both lesson-creation modes (random and
    manual) draw from, so a word already mastered is never offered again."""
    learned_ids = (
        db.query(WordProgress.word_id)
        .filter(WordProgress.user_id == user_id, WordProgress.score >= threshold)
        .subquery()
    )
    return db.query(Word).filter(Word.dictionary_id == dictionary_id, ~Word.id.in_(learned_ids)).all()


def _get_learned_pool(db: Session, user_id: int, dictionary_id: int, threshold: int) -> list[Word]:
    """The inverse of `_get_eligible_words`: words already learned (score >=
    threshold) with a translation to show -- "Правда или ложь"'s ONLY
    source of wrong-answer candidates, deliberately never a lesson's own
    words (see EXERCISE_AVAILABILITY's true_or_false check)."""
    learned_ids = (
        db.query(WordProgress.word_id)
        .filter(WordProgress.user_id == user_id, WordProgress.score >= threshold)
        .subquery()
    )
    words = db.query(Word).filter(Word.dictionary_id == dictionary_id, Word.id.in_(learned_ids)).all()
    return [w for w in words if w.translations]


def _true_or_false_available(db: Session, user: User, dictionary_id: int, lesson_word_ids: list[int], threshold: int) -> bool:
    """Requires at least one PREVIOUSLY learned word (never this lesson's
    own words) to draw wrong-answer candidates from -- confirmed as an
    always-required external pool, not a same-lesson fallback."""
    return len(_get_learned_pool(db, user.id, dictionary_id, threshold)) >= 1


def _matching_available(db: Session, user: User, dictionary_id: int, lesson_word_ids: list[int], threshold: int) -> bool:
    return len(lesson_word_ids) >= 2


def _build_word_available(db: Session, user: User, dictionary_id: int, lesson_word_ids: list[int], threshold: int) -> bool:
    _, min_word_length, _ = _get_build_word_settings(db)
    words = db.query(Word).filter(Word.id.in_(lesson_word_ids)).all()
    return any(len(w.word) >= min_word_length for w in words)


# The extensibility point section 13 of the spec asks for: a future
# exercise just adds its own (key -> availability check) entry here, never
# touches lesson-creation logic itself.
EXERCISE_AVAILABILITY = {
    TRUE_OR_FALSE_KEY: _true_or_false_available,
    MATCHING_KEY: _matching_available,
    BUILD_WORD_KEY: _build_word_available,
}


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


def _lesson_to_out(db: Session, lesson: Lesson, threshold: int) -> LessonOut:
    lesson_words = db.query(LessonWord).filter(LessonWord.lesson_id == lesson.id).order_by(LessonWord.id).all()
    word_ids = [lw.word_id for lw in lesson_words]
    progress_by_word: dict[int, int] = {}
    if word_ids:
        progress_by_word = {
            wp.word_id: wp.score
            for wp in db.query(WordProgress)
            .filter(WordProgress.user_id == lesson.user_id, WordProgress.word_id.in_(word_ids))
            .all()
        }

    words_out = []
    for lw in lesson_words:
        w = lw.word
        score = progress_by_word.get(lw.word_id, 0)
        primary = w.translations[0] if w.translations else None
        words_out.append(
            LessonWordOut(
                word_id=w.id,
                word=w.word,
                translation=primary.text if primary else None,
                score=score,
                is_learned=score >= threshold,
            )
        )

    exercise_keys = [
        le.exercise_key
        for le in db.query(LessonExercise).filter(LessonExercise.lesson_id == lesson.id).order_by(LessonExercise.id).all()
    ]

    return LessonOut(
        id=lesson.id,
        dictionary_id=lesson.dictionary_id,
        number=lesson.number,
        is_completed=lesson.is_completed,
        exercise_keys=exercise_keys,
        words=words_out,
    )


def _lesson_to_summary(db: Session, lesson: Lesson, threshold: int) -> LessonSummaryOut:
    """One row of the full lesson history -- see GET
    /dictionaries/{id}/lessons. Deliberately lighter than `_lesson_to_out`:
    just the counts the chain screen needs to render one link, not every
    word's own text/translation/score."""
    word_ids = [row[0] for row in db.query(LessonWord.word_id).filter(LessonWord.lesson_id == lesson.id).all()]
    learned_count = 0
    if word_ids:
        learned_count = (
            db.query(func.count(WordProgress.id))
            .filter(
                WordProgress.user_id == lesson.user_id,
                WordProgress.word_id.in_(word_ids),
                WordProgress.score >= threshold,
            )
            .scalar()
        )
    return LessonSummaryOut(
        id=lesson.id,
        number=lesson.number,
        is_completed=lesson.is_completed,
        word_count=len(word_ids),
        learned_count=learned_count,
    )


def _check_and_apply_lesson_completion(db: Session, lesson: Lesson, threshold: int) -> bool:
    """Recomputes from WordProgress every time rather than trusting any
    cached flag -- a lesson is complete exactly when ALL its words are at
    or above the threshold, never "most of them"."""
    if lesson.is_completed:
        return True
    word_ids = [row[0] for row in db.query(LessonWord.word_id).filter(LessonWord.lesson_id == lesson.id).all()]
    if not word_ids:
        return False
    learned_count = (
        db.query(func.count(WordProgress.id))
        .filter(WordProgress.user_id == lesson.user_id, WordProgress.word_id.in_(word_ids), WordProgress.score >= threshold)
        .scalar()
    )
    if learned_count == len(word_ids):
        lesson.is_completed = True
        lesson.completed_at = func.now()
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
    threshold = _get_threshold(db)
    words = _get_eligible_words(db, user.id, dictionary_id, threshold)
    return LessonCandidateWordsOut(
        dictionary_id=dictionary_id, available_count=len(words), words=[word_to_out(w) for w in words]
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
    return _lesson_to_out(db, lesson, _get_threshold(db))


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
    threshold = _get_threshold(db)
    lessons = (
        db.query(Lesson)
        .filter(Lesson.user_id == user.id, Lesson.dictionary_id == dictionary_id)
        .order_by(Lesson.number)
        .all()
    )
    return LessonListOut(
        dictionary_id=dictionary_id,
        lessons=[_lesson_to_summary(db, lesson, threshold) for lesson in lessons],
    )


@router.get("/lessons/{lesson_id}", response_model=LessonOut)
def get_lesson(
    lesson_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    lesson = _get_owned_lesson_or_404(db, user.id, lesson_id)
    return _lesson_to_out(db, lesson, _get_threshold(db))


@router.post("/lessons", response_model=LessonOut, status_code=status.HTTP_201_CREATED)
def create_lesson(
    payload: CreateLessonIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Freezes a specific set of word_ids (<=15, chosen randomly or by
    hand -- never both) into a new Lesson, then decides once which
    exercise types are available for that exact set (EXERCISE_AVAILABILITY)
    and persists that too (LessonExercise) -- never recomputed afterwards.
    Blocked while the current lesson for this (user, dictionary) isn't
    complete yet, enforced here AND at the database level (see Lesson's
    partial unique index) against a race between two requests."""
    dictionary = _get_published_dictionary_or_404(db, payload.dictionary_id)

    if _get_active_lesson(db, user.id, dictionary.id) is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Текущий урок ещё не завершён -- сначала пройдите его до конца",
        )

    threshold = _get_threshold(db)
    eligible_words = _get_eligible_words(db, user.id, dictionary.id, threshold)
    eligible_ids = {w.id for w in eligible_words}

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
        count = min(payload.random_count, len(eligible_ids))
        selected_ids = random.sample(sorted(eligible_ids), k=count)

    last_number = (
        db.query(func.max(Lesson.number))
        .filter(Lesson.user_id == user.id, Lesson.dictionary_id == dictionary.id)
        .scalar()
        or 0
    )

    lesson = Lesson(user_id=user.id, dictionary_id=dictionary.id, number=last_number + 1)
    db.add(lesson)
    db.flush()

    for word_id in selected_ids:
        db.add(LessonWord(lesson_id=lesson.id, word_id=word_id))

    for exercise_key, check in EXERCISE_AVAILABILITY.items():
        if check(db, user, dictionary.id, selected_ids, threshold):
            db.add(LessonExercise(lesson_id=lesson.id, exercise_key=exercise_key))

    db.commit()
    db.refresh(lesson)
    return _lesson_to_out(db, lesson, threshold)


# --- Lesson exercise rounds -------------------------------------------------
# Same response shapes as the old dictionary-scoped exercises
# (app/routers/exercises.py) -- only the word SOURCE changes, from
# LearnedWord to this lesson's fixed LessonWord set (plus, for True/False
# only, the separate previously-learned pool for wrong answers).


@router.get("/lessons/{lesson_id}/exercises/true-or-false", response_model=TrueOrFalseRoundOut)
def get_lesson_true_or_false_round(
    lesson_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    lesson = _get_owned_lesson_or_404(db, user.id, lesson_id)
    _require_lesson_exercise(db, lesson.id, TRUE_OR_FALSE_KEY)

    lesson_words = [lw.word for lw in lesson.words if lw.word.translations]
    threshold = _get_threshold(db)
    learned_pool = _get_learned_pool(db, user.id, lesson.dictionary_id, threshold)

    def primary_text(word: Word) -> str:
        return word.translations[0].text

    def primary_audio(word: Word) -> str | None:
        return url_for_key(word.translations[0].audio_key)

    items: list[TrueOrFalseItemOut] = []
    for word in lesson_words:
        real_text = primary_text(word)
        show_real = random.random() < 0.5

        fake_candidates = []
        if not show_real:
            fake_candidates = [w for w in learned_pool if w.id != word.id and primary_text(w) != real_text]
            if not fake_candidates:
                fake_candidates = [w for w in learned_pool if w.id != word.id]

        if show_real or not fake_candidates:
            shown_text, shown_audio, is_correct = real_text, primary_audio(word), True
        else:
            fake_word = random.choice(fake_candidates)
            shown_text, shown_audio, is_correct = primary_text(fake_word), primary_audio(fake_word), False

        items.append(
            TrueOrFalseItemOut(
                word_id=word.id,
                original=word.word,
                transcription=word.transcription,
                image_url=url_for_key(word.image_key),
                word_audio_url=url_for_key(word.word_audio_key),
                shown_translation=shown_text,
                shown_translation_audio_url=shown_audio,
                is_correct=is_correct,
            )
        )

    return TrueOrFalseRoundOut(dictionary_id=lesson.dictionary_id, available_count=len(lesson_words), items=items)


@router.get("/lessons/{lesson_id}/exercises/matching", response_model=ExerciseWordsOut)
def get_lesson_matching_round(
    lesson_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    lesson = _get_owned_lesson_or_404(db, user.id, lesson_id)
    _require_lesson_exercise(db, lesson.id, MATCHING_KEY)

    words = [lw.word for lw in lesson.words if lw.word.translations]
    return ExerciseWordsOut(
        dictionary_id=lesson.dictionary_id,
        exercise_key=MATCHING_KEY,
        available_count=len(words),
        words=[word_to_out(w) for w in words],
    )


@router.get("/lessons/{lesson_id}/exercises/build-word", response_model=BuildWordRoundOut)
def get_lesson_build_word_round(
    lesson_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    lesson = _get_owned_lesson_or_404(db, user.id, lesson_id)
    _require_lesson_exercise(db, lesson.id, BUILD_WORD_KEY)

    dictionary = db.get(Dictionary, lesson.dictionary_id)
    wrong_letter_count, min_word_length, case_sensitive = _get_build_word_settings(db)
    words = [lw.word for lw in lesson.words if len(lw.word.word) >= min_word_length]
    alphabet = dictionary.alphabet or "" if dictionary else ""

    items = [_build_word_item(w, alphabet, wrong_letter_count) for w in words]
    return BuildWordRoundOut(
        dictionary_id=lesson.dictionary_id,
        available_count=len(words),
        case_sensitive=case_sensitive,
        items=items,
    )


@router.post("/lessons/{lesson_id}/exercises/{exercise_key}/answers", response_model=SubmitAnswerOut)
def submit_answer(
    lesson_id: int,
    exercise_key: str,
    payload: SubmitAnswerIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """The one place a user's answer actually changes anything: moves
    `payload.word_id`'s WordProgress.score by this exercise's configured
    points (clamped 0-100), then checks whether that word -- and the whole
    lesson -- just crossed the learned threshold. `word_id` must belong to
    THIS lesson; scoring a word through an exercise it was never shown in
    is rejected, not silently accepted."""
    lesson = _get_owned_lesson_or_404(db, user.id, lesson_id)
    _require_lesson_exercise(db, lesson.id, exercise_key)

    in_lesson = (
        db.query(LessonWord).filter(LessonWord.lesson_id == lesson.id, LessonWord.word_id == payload.word_id).first()
        is not None
    )
    if not in_lesson:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Word not in this lesson")

    correct_points, incorrect_points = _get_points(db, exercise_key)
    delta = correct_points if payload.is_correct else -incorrect_points

    progress = (
        db.query(WordProgress)
        .filter(WordProgress.user_id == user.id, WordProgress.word_id == payload.word_id)
        .first()
    )
    if progress is None:
        progress = WordProgress(user_id=user.id, word_id=payload.word_id, score=0)
        db.add(progress)
        db.flush()

    progress.score = max(0, min(100, progress.score + delta))
    db.flush()  # this session's autoflush is off -- the completion check below must see this update

    threshold = _get_threshold(db)
    lesson_completed = _check_and_apply_lesson_completion(db, lesson, threshold)

    db.commit()
    return SubmitAnswerOut(
        word_id=payload.word_id,
        score=progress.score,
        is_learned=progress.score >= threshold,
        lesson_completed=lesson_completed,
    )


# --- Admin: global learning threshold --------------------------------------


@router.get("/learning-settings", response_model=LearningSettingsOut)
def get_learning_settings(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    return LearningSettingsOut(threshold_score=_get_threshold(db))


@router.put("/learning-settings", response_model=LearningSettingsOut)
def set_learning_settings(
    payload: LearningSettingsIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)
):
    settings = db.get(LearningSettings, 1)
    if settings is None:
        settings = LearningSettings(id=1, threshold_score=payload.threshold_score)
        db.add(settings)
    else:
        settings.threshold_score = payload.threshold_score
    db.commit()
    return LearningSettingsOut(threshold_score=settings.threshold_score)
