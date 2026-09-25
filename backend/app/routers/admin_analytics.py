"""«Аналитика пользователей»: an admin-only, read-only report over data
that already fully exists -- Word/WordForm, WordProgress, Phrase -- built
on the EXACT SAME "is this phrase available" definition as the user-facing
"Мои фразы" (see app.routers.phrases: `_tokenize`, `_get_learned_word_
tokens`). Nothing here writes anything, defines a second notion of
"learned", or duplicates that matching algorithm -- it only asks more
detailed questions of it (which specific word(s) are missing, and what
would learning one specific word unlock) than the boolean `_phrase_is_
available` alone can answer.
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin
from app.database import get_db
from app.models.dictionary import Dictionary
from app.models.phrase import Phrase
from app.models.user import User
from app.models.word import Word
from app.models.word_attempt import WordAttempt
from app.models.word_progress import WordProgress
from app.routers.lessons import _get_threshold
from app.routers.phrases import _get_learned_word_tokens, _tokenize
from app.word_levels import level_for_score_in, ordered_enabled_levels
from app.priority import calculate_priority
from app.schemas.analytics import (
    AnalyticsDictionaryOut,
    ExerciseAttemptStatsOut,
    MissingWordOut,
    PriorityBandSummaryOut,
    NearPhraseOut,
    OpenPhraseAnalyticsOut,
    UserPhraseAnalyticsOut,
    UserWordProgressOut,
    WordAttemptOut,
    WordDiagnosticsOut,
    WordImpactOut,
    WordLevelSummaryOut,
)

router = APIRouter(prefix="/admin/analytics", tags=["admin-analytics"])


@router.get("/dictionaries", response_model=list[AnalyticsDictionaryOut])
def list_analytics_dictionaries(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Only dictionaries with at least one Phrase -- a dictionary with none
    would always render an empty, useless report, so it's never offered as
    a choice here."""
    rows = (
        db.query(Dictionary, func.count(Phrase.id))
        .join(Phrase, Phrase.dictionary_id == Dictionary.id)
        .group_by(Dictionary.id)
        .order_by(Dictionary.id)
        .all()
    )
    return [
        AnalyticsDictionaryOut(id=d.id, name=d.name, language=d.language, phrase_count=count) for d, count in rows
    ]


def _build_token_to_word(db: Session, dictionary: Dictionary) -> tuple[dict[str, Word], list[Word]]:
    """Every token (a word's own text, or one of its OWN-LANGUAGE forms --
    same rule as `_get_learned_word_tokens`) mapped back to the Word it
    belongs to, for every Word in the dictionary, learned or not. This is
    what lets a "missing" token be reported as a real, nameable Word
    instead of just the raw phrase text."""
    words = db.query(Word).filter(Word.dictionary_id == dictionary.id).all()
    token_to_word: dict[str, Word] = {}
    for word in words:
        token_to_word.setdefault(word.word.strip().lower(), word)
        for form in word.forms:
            if form.language == dictionary.language:
                token_to_word.setdefault(form.text.strip().lower(), word)
    return token_to_word, words


def _phrase_progress(
    phrase: Phrase, learned_tokens: set[str], token_to_word: dict[str, Word]
) -> tuple[int, int, list[tuple[int | None, str]]]:
    """(total_count, learned_count, missing) for one phrase -- `missing` is
    the DISTINCT set of requirements still outstanding, one entry per
    distinct Word (never one entry per raw token: "может" and "могу" in
    the same phrase are one missing word, "мочь", not two), each as
    (word_id, display text) -- word_id is None when the token matches no
    Word/form in this dictionary at all (nothing learnable would ever
    satisfy it)."""
    requirements: dict[tuple[str, object], tuple[bool, int | None, str]] = {}
    for token in _tokenize(phrase.original):
        word = token_to_word.get(token)
        key = ("word", word.id) if word is not None else ("token", token)
        if key in requirements:
            continue
        satisfied = token in learned_tokens
        display_text = word.word if word is not None else token
        requirements[key] = (satisfied, word.id if word is not None else None, display_text)

    total = len(requirements)
    learned = sum(1 for satisfied, _, _ in requirements.values() if satisfied)
    missing = [(word_id, text) for satisfied, word_id, text in requirements.values() if not satisfied]
    return total, learned, missing


@router.get("/users/{user_id}", response_model=UserPhraseAnalyticsOut)
def get_user_phrase_analytics(
    user_id: int,
    dictionary_id: int,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    dictionary = db.get(Dictionary, dictionary_id)
    if dictionary is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")

    threshold = _get_threshold(db)
    learned_tokens = _get_learned_word_tokens(db, user.id, dictionary)
    token_to_word, all_words = _build_token_to_word(db, dictionary)

    learned_word_count = (
        db.query(func.count(Word.id))
        .join(WordProgress, WordProgress.word_id == Word.id)
        .filter(WordProgress.user_id == user.id, WordProgress.score >= threshold, Word.dictionary_id == dictionary.id)
        .scalar()
    )

    phrases = (
        db.query(Phrase)
        .filter(Phrase.dictionary_id == dictionary.id)
        .order_by(Phrase.id)
        .all()
    )

    def category_name(p: Phrase) -> str | None:
        return p.category.name if p.category is not None else None

    open_phrases: list[OpenPhraseAnalyticsOut] = []
    near_phrases: list[NearPhraseOut] = []
    # word_id -> [display text, [phrase originals it would immediately open]]
    word_impact: dict[int, list] = {}

    for phrase in phrases:
        total, learned, missing = _phrase_progress(phrase, learned_tokens, token_to_word)
        if total > 0 and learned == total:
            open_phrases.append(
                OpenPhraseAnalyticsOut(
                    phrase_id=phrase.id,
                    original=phrase.original,
                    translation_tg=phrase.translation_tg,
                    category_name=category_name(phrase),
                )
            )
            continue

        near_phrases.append(
            NearPhraseOut(
                phrase_id=phrase.id,
                original=phrase.original,
                translation_tg=phrase.translation_tg,
                category_name=category_name(phrase),
                learned_count=learned,
                total_count=total,
                missing_words=[MissingWordOut(word_id=wid, text=text) for wid, text in missing],
            )
        )

        if len(missing) == 1 and missing[0][0] is not None:
            word_id, text = missing[0]
            entry = word_impact.setdefault(word_id, [text, []])
            entry[1].append(phrase.original)

    near_phrases.sort(key=lambda p: (p.total_count - p.learned_count, p.total_count, p.phrase_id))

    top_words = [
        WordImpactOut(word_id=word_id, word=text, new_phrase_count=len(originals), sample_phrases=originals)
        for word_id, (text, originals) in word_impact.items()
    ]
    top_words.sort(key=lambda w: (-w.new_phrase_count, w.word))

    return UserPhraseAnalyticsOut(
        user_id=user.id,
        user_login=user.login,
        dictionary_id=dictionary.id,
        threshold=threshold,
        learned_word_count=learned_word_count,
        total_word_count=len(all_words),
        open_phrase_count=len(open_phrases),
        total_phrase_count=len(phrases),
        remaining_phrase_count=len(phrases) - len(open_phrases),
        open_phrases=open_phrases,
        near_phrases=near_phrases,
        top_words=top_words,
    )


# --- Per-word diagnostics: WordProgress + WordAttempt, both read-only ------
# Entirely separate concern from the phrase report above (that one reads
# Word/Phrase/WordProgress; this reads WordProgress/WordAttempt) -- sharing
# only the router prefix and the same "pick a user" step in Admin Web.


def _word_level_summary(db: Session, score: int) -> WordLevelSummaryOut | None:
    level = level_for_score_in(ordered_enabled_levels(db), score)
    if level is None:
        return None
    return WordLevelSummaryOut(
        id=level.id, name=level.name, min_points=level.min_points, max_points=level.max_points,
        priority_weight=level.priority_weight,
    )


@router.get("/users/{user_id}/words", response_model=list[UserWordProgressOut])
def list_user_word_progress(
    user_id: int,
    dictionary_id: int,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Every Word in `dictionary_id` this user has a WordProgress row for
    (i.e. has been through at least one real attempt at, ever, in a Lesson
    or a Quest) -- the word-picker list on the admin's «Диагностика слова»
    page. `total_attempts` is a plain count of WordAttempt, grouped once
    here rather than N+1 queried per word."""
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    if db.get(Dictionary, dictionary_id) is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")

    levels = ordered_enabled_levels(db)

    attempt_counts = dict(
        db.query(WordAttempt.word_id, func.count(WordAttempt.id))
        .filter(WordAttempt.user_id == user_id)
        .group_by(WordAttempt.word_id)
        .all()
    )

    rows = (
        db.query(Word, WordProgress)
        .join(WordProgress, WordProgress.word_id == Word.id)
        .filter(WordProgress.user_id == user_id, Word.dictionary_id == dictionary_id)
        .order_by(WordProgress.updated_at.desc())
        .all()
    )

    out: list[UserWordProgressOut] = []
    for word, progress in rows:
        primary = word.translations[0].text if word.translations else None
        level = level_for_score_in(levels, progress.score)
        out.append(
            UserWordProgressOut(
                word_id=word.id,
                word=word.word,
                translation=primary,
                dictionary_id=word.dictionary_id,
                score=progress.score,
                level=WordLevelSummaryOut(
                    id=level.id, name=level.name, min_points=level.min_points, max_points=level.max_points,
                    priority_weight=level.priority_weight,
                )
                if level is not None
                else None,
                total_attempts=attempt_counts.get(word.id, 0),
                updated_at=progress.updated_at,
            )
        )
    return out


@router.get("/users/{user_id}/words/{word_id}", response_model=WordDiagnosticsOut)
def get_word_diagnostics(
    user_id: int,
    word_id: int,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """The full «Диагностика слова» picture for one (user, word): current
    level/score (re-derived from WordProgress, never cached), and every
    number below it computed by aggregating WordAttempt -- total, the
    per-exercise breakdown, the last attempt, and the complete history --
    never a second stored counter that could drift from it."""
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    word = db.get(Word, word_id)
    if word is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Word not found")

    progress = db.query(WordProgress).filter(WordProgress.user_id == user_id, WordProgress.word_id == word_id).first()
    score = progress.score if progress is not None else 0

    attempts = (
        db.query(WordAttempt)
        .filter(WordAttempt.user_id == user_id, WordAttempt.word_id == word_id)
        .order_by(WordAttempt.created_at.asc())
        .all()
    )

    by_exercise: dict[str, list[int]] = {}  # exercise_key -> [attempts, correct, errors]
    for a in attempts:
        bucket = by_exercise.setdefault(a.exercise_key, [0, 0, 0])
        bucket[0] += 1
        bucket[1 if a.is_correct else 2] += 1

    total_correct = sum(1 for a in attempts if a.is_correct)
    primary = word.translations[0].text if word.translations else None
    priority = calculate_priority(db, user_id, word_id)

    def _attempt_out(a: WordAttempt) -> WordAttemptOut:
        return WordAttemptOut(exercise_key=a.exercise_key, is_correct=a.is_correct, score_after=a.score_after, created_at=a.created_at)

    return WordDiagnosticsOut(
        user_id=user.id,
        user_login=user.login,
        word_id=word.id,
        word=word.word,
        translation=primary,
        score=score,
        level=_word_level_summary(db, score),
        total_attempts=len(attempts),
        total_correct=total_correct,
        total_errors=len(attempts) - total_correct,
        by_exercise=[
            ExerciseAttemptStatsOut(exercise_key=key, total_attempts=a, total_correct=c, total_errors=e)
            for key, (a, c, e) in by_exercise.items()
        ],
        last_attempt=_attempt_out(attempts[-1]) if attempts else None,
        history=[_attempt_out(a) for a in attempts],
        priority_score=priority.score,
        priority_level=PriorityBandSummaryOut(id=priority.level.id, name=priority.level.name) if priority.level else None,
        stability_percent=priority.stability_percent,
        stability_level=PriorityBandSummaryOut(id=priority.stability_band.id, name=priority.stability_band.name)
        if priority.stability_band
        else None,
        days_since_last_attempt=priority.days_since_last_attempt,
        recency_level=PriorityBandSummaryOut(id=priority.recency_band.id, name=priority.recency_band.name)
        if priority.recency_band
        else None,
        level_contribution=priority.level_contribution,
        recent_errors_contribution=priority.recent_errors_contribution,
        recency_contribution=priority.recency_contribution,
        stability_contribution=priority.stability_contribution,
    )
