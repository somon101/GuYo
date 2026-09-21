"""User-facing Quests: list what's currently attemptable, fetch a round
for one word, submit the result. Entirely separate from /lessons -- no
LessonWord/LessonExercise involved anywhere here."""

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.achievements import check_and_grant_achievements, record_activity
from app.core.deps import get_current_user
from app.database import get_db
from app.exercises.common import get_threshold
from app.models.quest import Quest
from app.models.word import Word
from app.models.word_level import WordLevel
from app.models.user import User
from app.quests import build_quest_round, candidate_words_for_quest, complete_quest_attempt, pick_quest_word
from app.rating import award_word_points_if_new, get_or_create_user_rating
from app.schemas.quest import AvailableQuestOut, QuestAnswerIn, QuestAnswerOut, QuestRoundOut

router = APIRouter(prefix="/quests", tags=["quests"])


def _level_name(db: Session, word_level_id: int) -> str:
    level = db.get(WordLevel, word_level_id)
    return level.name if level else "?"


@router.get("", response_model=list[AvailableQuestOut])
def list_quests(
    dictionary_id: int = Query(...), db: Session = Depends(get_db), user: User = Depends(get_current_user)
):
    quests = db.query(Quest).filter(Quest.enabled.is_(True)).order_by(Quest.order, Quest.id).all()
    return [
        AvailableQuestOut(
            id=q.id,
            name=q.name,
            word_level_name=_level_name(db, q.word_level_id),
            exercise_key=q.exercise_key,
            reward_points=q.reward_points,
            available=pick_quest_word(db, user, q, dictionary_id) is not None,
        )
        for q in quests
    ]


def _get_enabled_quest_or_404(db: Session, quest_id: int) -> Quest:
    quest = db.get(Quest, quest_id)
    if quest is None or not quest.enabled:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Quest not found")
    return quest


@router.get("/{quest_id}/round", response_model=QuestRoundOut)
def get_quest_round(
    quest_id: int,
    dictionary_id: int = Query(...),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    quest = _get_enabled_quest_or_404(db, quest_id)
    word = pick_quest_word(db, user, quest, dictionary_id)
    if word is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Нет доступных слов для этого квеста")

    round_data = build_quest_round(db, user, quest, dictionary_id, word)
    return QuestRoundOut(quest_id=quest.id, word_id=word.id, exercise_key=quest.exercise_key, payload=round_data.model_dump())


@router.post("/{quest_id}/answers", response_model=QuestAnswerOut)
def submit_quest_answer(
    quest_id: int,
    payload: QuestAnswerIn,
    dictionary_id: int = Query(...),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    quest = _get_enabled_quest_or_404(db, quest_id)

    word = db.get(Word, payload.word_id)
    if word is None or word.dictionary_id != dictionary_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Word not found in this dictionary")

    candidates = {w.id for w in candidate_words_for_quest(db, user, quest, dictionary_id)}
    if payload.word_id not in candidates:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Это слово больше недоступно для этого квеста (уже использовано сегодня или сменило уровень)",
        )

    rating_before = get_or_create_user_rating(db, user.id).total_points

    new_score = complete_quest_attempt(db, user, quest, word, payload.is_correct)

    # A quest can push a word's reinforcement score across the SAME
    # learned threshold a Lesson answer would -- see app/exercises/
    # common.py's get_threshold (now derived from the WordLevel ladder).
    # When that happens here, it must trigger the exact same downstream
    # effects a Lesson crossing already does (never a quest-only silo):
    # the "words_learned"/"phrases_opened" achievements and the existing
    # per-learned-word rating bonus (app/rating/service.py's
    # award_word_points_if_new) -- both already idempotent per word, so
    # calling them here is safe even if the word was already learned via
    # a Lesson earlier.
    if new_score >= get_threshold(db):
        check_and_grant_achievements(db, user, "phrases_opened")
        check_and_grant_achievements(db, user, "words_learned")
        award_word_points_if_new(db, user, word.id)

    record_activity(db, user)

    rating_after = get_or_create_user_rating(db, user.id).total_points
    reward_granted = rating_after - rating_before

    db.commit()
    return QuestAnswerOut(word_id=word.id, score=new_score, is_correct=payload.is_correct, reward_granted=reward_granted)
