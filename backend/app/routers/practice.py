"""«Практика»: self-directed rounds over a user's own LEARNED words
(WordProgress.score >= threshold -- the same get_learned_pool every other
"learned words" feature already reads from), for every one of the 5
word-scoped exercise types.

This deliberately does NOT re-implement any exercise -- it randomly
samples words from get_learned_pool, feasibility-filters them with
app/quests/rounds.py's own is_quest_word_feasible, and for the 4
per-item types calls that same module's single-target round builder once
per sampled word, concatenating the results into one ordinary
multi-item round. The wire shape is therefore IDENTICAL to a Lesson's own
round for that exercise_key -- the client parses it with the exact same
model, and renders it with the exact same widget, it already has.

"Сопоставление" needs no per-word builder at all: like a Lesson's own
matching round, it is simply N learned words for the client to shuffle
into a board -- see build_matching_words below.

No answer is ever submitted here, and nothing in this file touches
WordProgress, UserRating or any achievement -- Practice is self-testing,
the same "no score of its own" contract Практика's phrase exercises
(build_phrase/build_phrase_by_ear) already established. A round is
read-only from end to end.
"""

import random

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.database import get_db
from app.exercises import build_word, listen_word, matching, speaking_word, true_or_false
from app.exercises.common import get_learned_pool, get_threshold
from app.models.dictionary import Dictionary
from app.models.user import User
from app.models.word import Word
from app.quests.rounds import (
    build_build_word_round,
    build_listen_word_round,
    build_speaking_word_round,
    build_true_or_false_round,
    is_quest_word_feasible,
)
from app.routers.words import word_to_out
from app.schemas.exercise import BuildWordRoundOut, ExerciseWordsOut, TrueOrFalseRoundOut
from app.schemas.lesson import ListenWordRoundOut, SpeakingWordRoundOut

router = APIRouter(prefix="/dictionaries/{dictionary_id}/practice", tags=["practice"])

# A bite-sized session, same order of magnitude as build_phrase_screen.
# dart's own _roundSize -- Practice is meant to be played in short bursts,
# not "every learned word at once".
ROUND_SIZE = 10


def _get_dictionary_or_404(db: Session, dictionary_id: int) -> Dictionary:
    dictionary = db.get(Dictionary, dictionary_id)
    if dictionary is None or not dictionary.is_published:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")
    return dictionary


def _sample_feasible_words(
    db: Session, user: User, dictionary_id: int, threshold: int, exercise_key: str, pool: list[Word]
) -> tuple[list[Word], int]:
    """Feasibility-filters `pool` for `exercise_key` (mirrors each Lesson
    exercise module's own is_available, single-word) and returns a random
    sample of up to ROUND_SIZE of them, alongside how many were feasible
    in total -- the same "available_count vs len(items)" distinction every
    other round response already carries."""
    feasible = [w for w in pool if is_quest_word_feasible(db, user, dictionary_id, threshold, exercise_key, w)]
    sample = feasible[:]
    random.shuffle(sample)
    return sample[:ROUND_SIZE], len(feasible)


@router.get("/true-or-false", response_model=TrueOrFalseRoundOut)
def get_practice_true_or_false_round(
    dictionary_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)
):
    _get_dictionary_or_404(db, dictionary_id)
    threshold = get_threshold(db)
    pool = get_learned_pool(db, user.id, dictionary_id, threshold)
    selected, available_count = _sample_feasible_words(db, user, dictionary_id, threshold, true_or_false.KEY, pool)
    items = [build_true_or_false_round(db, user, dictionary_id, threshold, w).items[0] for w in selected]
    return TrueOrFalseRoundOut(dictionary_id=dictionary_id, available_count=available_count, items=items)


@router.get("/matching", response_model=ExerciseWordsOut)
def get_practice_matching_words(dictionary_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """No per-word round builder needed: exactly like a Lesson's own
    matching round, this is just N learned words (already guaranteed to
    have a translation by get_learned_pool) for the client to shuffle into
    a board -- the SAME MatchingBoard widget a Lesson uses to play one."""
    _get_dictionary_or_404(db, dictionary_id)
    threshold = get_threshold(db)
    pool = get_learned_pool(db, user.id, dictionary_id, threshold)
    sample = pool[:]
    random.shuffle(sample)
    selected = sample[:ROUND_SIZE]
    return ExerciseWordsOut(
        dictionary_id=dictionary_id, exercise_key=matching.KEY, available_count=len(pool), words=[word_to_out(w) for w in selected]
    )


@router.get("/build-word", response_model=BuildWordRoundOut)
def get_practice_build_word_round(dictionary_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    _get_dictionary_or_404(db, dictionary_id)
    threshold = get_threshold(db)
    pool = get_learned_pool(db, user.id, dictionary_id, threshold)
    selected, available_count = _sample_feasible_words(db, user, dictionary_id, threshold, build_word.KEY, pool)
    rounds = [build_build_word_round(db, dictionary_id, w) for w in selected]
    case_sensitive = rounds[0].case_sensitive if rounds else False
    items = [r.items[0] for r in rounds]
    return BuildWordRoundOut(dictionary_id=dictionary_id, available_count=available_count, case_sensitive=case_sensitive, items=items)


@router.get("/speaking-word", response_model=SpeakingWordRoundOut)
def get_practice_speaking_word_round(dictionary_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    _get_dictionary_or_404(db, dictionary_id)
    threshold = get_threshold(db)
    pool = get_learned_pool(db, user.id, dictionary_id, threshold)
    selected, available_count = _sample_feasible_words(db, user, dictionary_id, threshold, speaking_word.KEY, pool)
    rounds = [build_speaking_word_round(db, dictionary_id, w) for w in selected]
    match_threshold = rounds[0].match_threshold if rounds else speaking_word.get_match_threshold(db)
    items = [r.items[0] for r in rounds]
    return SpeakingWordRoundOut(dictionary_id=dictionary_id, available_count=available_count, match_threshold=match_threshold, items=items)


@router.get("/listen-word", response_model=ListenWordRoundOut)
def get_practice_listen_word_round(dictionary_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    _get_dictionary_or_404(db, dictionary_id)
    threshold = get_threshold(db)
    pool = get_learned_pool(db, user.id, dictionary_id, threshold)
    selected, available_count = _sample_feasible_words(db, user, dictionary_id, threshold, listen_word.KEY, pool)
    items = [build_listen_word_round(db, user, dictionary_id, threshold, w).items[0] for w in selected]
    return ListenWordRoundOut(dictionary_id=dictionary_id, available_count=available_count, items=items)
