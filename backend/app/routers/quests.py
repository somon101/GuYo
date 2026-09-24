"""User-facing Quests: list what's currently attemptable, fetch a round
for one word, submit the result. Entirely separate from /lessons -- no
LessonWord/LessonExercise involved anywhere here."""

import math

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.achievements import check_and_grant_achievements, record_activity
from app.core.dates import utc_now
from app.core.deps import get_current_user
from app.core.storage import url_for_key
from app.database import get_db
from app.exercises.common import get_threshold
from app.models.quest import Quest
from app.models.rating import Season, UserWordPoints
from app.models.word import Word
from app.models.word_level import WordLevel
from app.models.user import User
from app.quests import (
    build_quest_round,
    candidate_words_for_quest,
    complete_quest_attempt,
    dushanbe_day_bounds_utc,
    pick_quest_word,
    quest_completions_today,
)
from app.rating import (
    award_word_points_if_new,
    current_rank_for_points,
    get_active_season,
    get_or_create_user_rating,
    get_rating_settings,
    rank_position_for_user,
    sync_season_states,
)
from app.schemas.quest import (
    AvailableQuestOut,
    QuestAnswerIn,
    QuestAnswerOut,
    QuestRoundOut,
    SeasonQuestOverviewOut,
)
from app.schemas.rating import SeasonOut, rank_public_out

router = APIRouter(prefix="/quests", tags=["quests"])


def _level_name(db: Session, word_level_id: int) -> str:
    level = db.get(WordLevel, word_level_id)
    return level.name if level else "?"


def _season_out(season: Season) -> SeasonOut:
    """The season exactly as the admin configured it -- icon_url is the
    picture uploaded in the season settings, never a second image owned
    by this screen."""
    return SeasonOut(
        id=season.id,
        name=season.name,
        starts_at=season.starts_at,
        ends_at=season.ends_at,
        ended_at=season.ended_at,
        status=season.status,
        icon_url=url_for_key(season.icon_key),
    )


def _available_quests(db: Session, user: User, dictionary_id: int) -> list[AvailableQuestOut]:
    """Every enabled quest with this user's own state for it today. The
    one place that list is built, so GET /quests and the overview below
    can never disagree about what exists or how far along it is."""
    quests = db.query(Quest).filter(Quest.enabled.is_(True)).order_by(Quest.order, Quest.id).all()
    done_today = quest_completions_today(db, user.id)
    out = []
    for q in quests:
        completed = done_today.get(q.id, 0)
        out.append(
            AvailableQuestOut(
                id=q.id,
                name=q.name,
                word_level_name=_level_name(db, q.word_level_id),
                exercise_key=q.exercise_key,
                reward_points=q.reward_points,
                available=pick_quest_word(db, user, q, dictionary_id) is not None,
                daily_target=q.daily_target,
                completed_today=completed,
                is_done_today=completed >= q.daily_target,
            )
        )
    return out


@router.get("", response_model=list[AvailableQuestOut])
def list_quests(
    dictionary_id: int = Query(...), db: Session = Depends(get_db), user: User = Depends(get_current_user)
):
    return _available_quests(db, user, dictionary_id)


@router.get("/overview", response_model=SeasonQuestOverviewOut)
def get_season_quest_overview(
    dictionary_id: int = Query(...), db: Session = Depends(get_db), user: User = Depends(get_current_user)
):
    """One round trip for the home screen's "Квесты сезона" block and the
    season quests screen behind it. Purely a read: it assembles the active
    season, this user's rating standing and their quest progress today out
    of the tables those systems already own, and writes nothing.

    "Today" is the Asia/Dushanbe day -- the same boundary quests already
    reset on, so "очков сегодня" and "квестов выполнено сегодня" can never
    disagree with each other about when the day turned over."""
    # The schedule decides which season is live; syncing first means this
    # screen can never show one whose period has already passed.
    sync_season_states(db)
    season = get_active_season(db)

    # The season's own timeline, in whole days rounded UP: with half a day
    # to go the season still has "1 день", and only a season that is
    # actually over shows 0. Both null for a season with no scheduled end
    # -- there is nothing to count down to and no range to draw.
    days_left = None
    days_total = None
    if season is not None and season.ends_at is not None:
        now = utc_now()
        days_left = max(0, math.ceil((season.ends_at - now).total_seconds() / 86400))
        # At least 1, so a same-day season is a full bar rather than a
        # division by zero.
        days_total = max(1, math.ceil((season.ends_at - season.starts_at).total_seconds() / 86400))

    rating = get_or_create_user_rating(db, user.id)
    rank = current_rank_for_points(db, rating.total_points)

    day_start, day_end = dushanbe_day_bounds_utc()

    # Points earned today, from the two ledgers that already record every
    # grant: one row per newly learned word, and one row per word a quest
    # consumed (whose reward is that quest's own reward_points).
    word_rows = (
        db.query(UserWordPoints.points_awarded)
        .filter(
            UserWordPoints.user_id == user.id,
            UserWordPoints.awarded_at >= day_start,
            UserWordPoints.awarded_at <= day_end,
        )
        .all()
    )
    words_learned_today = len(word_rows)
    points_today = sum(row[0] for row in word_rows)

    done_today = quest_completions_today(db, user.id)
    if done_today:
        rewards = {
            q.id: q.reward_points for q in db.query(Quest).filter(Quest.id.in_(list(done_today))).all()
        }
        points_today += sum(rewards.get(quest_id, 0) * count for quest_id, count in done_today.items())

    quests = _available_quests(db, user, dictionary_id)

    return SeasonQuestOverviewOut(
        season=_season_out(season) if season is not None else None,
        days_left=days_left,
        days_total=days_total,
        points_today=points_today,
        total_points=rating.total_points,
        rank=rank_public_out(rank),
        rank_position=rank_position_for_user(db, rank, rating) if rank else None,
        quests_done_today=sum(1 for q in quests if q.is_done_today),
        quests_total=len(quests),
        points_per_learned_word=get_rating_settings(db).points_per_learned_word,
        words_learned_today=words_learned_today,
        quests=quests,
    )


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
