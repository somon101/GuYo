from datetime import timedelta

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.content_language import reading_language
from app.achievements.conditions import streak_with_freezes
from app.achievements import CONDITION_TYPES, grant_all_due_achievements, lessons_completed_count, streak_days_count, words_learned_count
from app.core.dates import dushanbe_today, utc_now
from app.core.deps import get_current_admin, get_current_user, require_current_app
from app.core.public_id import generate_public_id
from app.core.security import hash_password
from app.core.storage import delete_by_key, save_bytes, url_for_key
from app.database import get_db
from app.models.achievement import VISIBILITY_HIDDEN, Achievement, UserAchievement, UserActivityDay
from app.models.admin import Admin
from app.models.rating import SeasonHistory
from app.models.user import User
from app.premium import effective_premium_until
from app.rating import (
    current_rank_for_points,
    get_active_season,
    get_or_create_user_rating,
    get_rating_settings,
    next_rank_for_points,
    position_changes,
    rank_position_for_user,
    refresh_rank_positions,
    sync_season_states,
)
from app.schemas.achievement import UserAchievementOut
from app.schemas.rating import SeasonHistoryOut, SeasonOut, UserRatingOut, rank_public_out
from app.schemas.user import UserCreate, UserOut, UserProfileOut, UserUpdateIn

router = APIRouter(prefix="/users", tags=["users"])

# Generous enough for a real phone photo, small enough that nobody's
# profile picture eats meaningful storage -- same "don't let a user upload
# something absurd" reasoning the ZIP import size checks already use
# elsewhere in this codebase.
MAX_AVATAR_BYTES = 5 * 1024 * 1024
ALLOWED_AVATAR_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp"}
# Keyed by the SAME validated content_type above -- the extension a stored
# avatar file gets on disk must come from here, never from the client's own
# filename. A real Android gallery pick can hand back a content:// name
# with no extension at all (or the wrong one); storing under that name
# leaves StaticFiles unable to guess a Content-Type on the way back out,
# so it serves text/plain for a real photo and the client's Image.network
# silently fails to render it -- exactly the bug this fixes.
_AVATAR_EXTENSION_BY_CONTENT_TYPE = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
}


@router.get("", response_model=list[UserOut])
def list_users(db: Session = Depends(get_db), _admin: Admin = Depends(get_current_admin)):
    return db.query(User).order_by(User.id).all()


def new_user_row(
    db: Session,
    *,
    login: str,
    password: str,
    first_name: str,
    last_name: str,
    email: str,
    learning_language: str | None = None,
    age_group: str | None = None,
    learning_goal: str | None = None,
    referral_source: str | None = None,
    learning_topics: list[str] | None = None,
    ui_language: str = "ru",
    translation_language: str = "tg",
    google_sub: str | None = None,
) -> User:
    """The one place a User row is ever built -- admin_router's
    create_user below and auth.py's public register_user both call this,
    so "is this login/email already taken" and the 9-digit id can never
    drift between the two entry points. Does not commit; the caller owns
    the transaction (register_user also needs the row's id for the token
    it issues right after)."""
    if db.query(User).filter(User.login == login).first() is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Login already taken")
    if db.query(User).filter(User.email == email).first() is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Этот адрес почты уже занят")

    user = User(
        public_id=generate_public_id(db),
        login=login,
        password_hash=hash_password(password),
        first_name=first_name.strip(),
        last_name=last_name.strip(),
        email=email,
        learning_language=learning_language,
        age_group=age_group,
        learning_goal=learning_goal,
        referral_source=referral_source,
        learning_topics=learning_topics,
        ui_language=ui_language,
        translation_language=reading_language(ui_language, translation_language),
        google_sub=google_sub,
    )
    db.add(user)
    db.flush()
    return user


@router.post("", response_model=UserOut, status_code=status.HTTP_201_CREATED)
def create_user(payload: UserCreate, db: Session = Depends(get_db), _admin: Admin = Depends(get_current_admin)):
    """Creates an account. Name, surname and email are required here and
    only here -- the columns stay nullable so accounts made before they
    existed keep working (see app/models/user.py).

    The 9-digit account number is generated, never supplied: it is the
    user's permanent public identity and nobody gets to pick it."""
    user = new_user_row(
        db,
        login=payload.login,
        password=payload.password,
        first_name=payload.first_name,
        last_name=payload.last_name,
        email=payload.email,
    )
    db.commit()
    db.refresh(user)
    return user


@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_user(user_id: int, db: Session = Depends(get_db), _admin: Admin = Depends(get_current_admin)):
    """Permanently removes a user and everything scoped to them -- every
    other table's own user_id column is declared ondelete="CASCADE"
    (UserRating, WordProgress, Lesson/LessonWord/LessonExercise,
    UserAchievement, SeasonHistory, UserQuestWordDay, LearningSession,
    UserDailySlogan, Notification, PremiumGrant, PromoActivation, ...),
    so this one delete is enough; nothing here re-implements that cleanup
    by hand. Mainly for removing test/bot accounts (e.g. ones seeded to
    exercise the rating ladder) without leaving orphaned rows anywhere --
    a REAL user's own account is never deleted through any UI path today,
    only this direct admin call."""
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    avatar_key = user.avatar_key
    db.delete(user)
    db.commit()
    delete_by_key(avatar_key)


def _profile_out(db: Session, user: User) -> UserProfileOut:
    return UserProfileOut(
        id=user.id,
        public_id=user.public_id,
        login=user.login,
        first_name=user.first_name,
        last_name=user.last_name,
        email=user.email,
        avatar_url=url_for_key(user.avatar_key),
        current_streak_days=streak_days_count(db, user),
        lessons_completed=lessons_completed_count(db, user),
        words_learned=words_learned_count(db, user),
        premium_until=effective_premium_until(db, user),
        learning_language=user.learning_language,
        age_group=user.age_group,
        learning_goal=user.learning_goal,
        referral_source=user.referral_source,
        learning_topics=user.learning_topics,
        ui_language=user.ui_language,
        translation_language=user.translation_language,
    )


@router.get("/me/streak")
def get_my_streak(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """The streak sheet: the current streak and which days of the last two
    weeks had activity, on the same Asia/Dushanbe day boundary the streak
    itself counts by."""
    today = dushanbe_today()
    since = today - timedelta(days=13)
    active = sorted(
        row[0]
        for row in db.query(UserActivityDay.activity_date)
        .filter(UserActivityDay.user_id == user.id, UserActivityDay.activity_date >= since)
        .all()
    )
    streak, frozen = streak_with_freezes(db, user)
    return {
        "current_streak_days": streak,
        "today": today.isoformat(),
        "active_dates": [d.isoformat() for d in active],
        # Missed days a weekly freeze covered (see streak_with_freezes).
        "frozen_dates": [d.isoformat() for d in frozen if d >= since],
    }


@router.get("/me/profile", response_model=UserProfileOut)
def get_my_profile(db: Session = Depends(get_db), user: User = Depends(get_current_user),
    _app: None = Depends(require_current_app)):
    return _profile_out(db, user)


@router.patch("/me/profile", response_model=UserProfileOut)
def update_my_profile(
    payload: UserUpdateIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """What the "Настройки" screen saves. Only the fields actually sent
    are changed, so editing one thing never blanks another.

    The photo is not here -- it is a file, and keeps its own upload/delete
    endpoints below. Neither is the account number, which is permanent, or
    the password, which is its own operation.

    Login and email are unique, so both are checked against OTHER accounts
    before the write; the database's own constraints are still what
    ultimately guarantee it."""
    fields = payload.model_dump(exclude_unset=True)

    if "login" in fields:
        login = fields["login"].strip()
        taken = db.query(User).filter(User.login == login, User.id != user.id).first()
        if taken is not None:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Этот логин уже занят")
        user.login = login

    # The email is the linked Google account's and can't be changed here.
    if "email" in fields and fields["email"] != user.email:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Почту изменить нельзя: она привязана к Google")

    if "first_name" in fields:
        user.first_name = fields["first_name"].strip() if fields["first_name"] else None
    if "last_name" in fields:
        user.last_name = fields["last_name"].strip() if fields["last_name"] else None
    if fields.get("translation_language"):
        user.translation_language = fields["translation_language"]
    if fields.get("ui_language"):
        user.ui_language = fields["ui_language"]
    # A Tajik or Uzbek interface always reads its own language.
    user.translation_language = reading_language(user.ui_language, user.translation_language)
    if "learning_topics" in fields:
        user.learning_topics = list(dict.fromkeys(fields["learning_topics"] or []))

    db.commit()
    db.refresh(user)
    return _profile_out(db, user)


@router.post("/me/avatar", response_model=UserProfileOut)
def upload_my_avatar(
    avatar: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Replaces this user's avatar. Rejects anything not a real, reasonably
    sized image up front rather than silently accepting it -- the previous
    file (if any) is only deleted once the new one has actually been
    validated and saved, so a rejected upload never leaves the user with
    no photo at all."""
    if avatar.content_type not in ALLOWED_AVATAR_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Допустимые форматы: JPEG, PNG, WEBP",
        )
    data = avatar.file.read()
    if len(data) > MAX_AVATAR_BYTES:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Файл слишком большой (максимум 5 МБ)")
    if len(data) == 0:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Пустой файл")

    extension = _AVATAR_EXTENSION_BY_CONTENT_TYPE[avatar.content_type]
    new_key = save_bytes(data, subdir=f"users/{user.id}/avatar", filename_hint=f"avatar{extension}")
    old_key = user.avatar_key
    user.avatar_key = new_key
    db.commit()
    delete_by_key(old_key)
    db.refresh(user)
    return _profile_out(db, user)


@router.delete("/me/avatar", response_model=UserProfileOut)
def delete_my_avatar(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Clears the avatar -- the client falls back to its generated default
    avatar the moment `avatar_url` comes back null, nothing else to do
    here."""
    old_key = user.avatar_key
    user.avatar_key = None
    db.commit()
    delete_by_key(old_key)
    return _profile_out(db, user)


@router.get("/me/achievements", response_model=list[UserAchievementOut])
def get_my_achievements(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Every ENABLED achievement, each with this user's own earned status
    and (for the ones not yet earned) their current progress -- computed
    fresh here, on read, so it's always accurate even if the user earned
    something through an action that hasn't explicitly re-run the granting
    check (see app/achievements/service.py) since. The backend decides all
    of this; nothing about "have I earned this" is computed in Flutter."""
    achievements = (
        db.query(Achievement).filter(Achievement.enabled.is_(True)).order_by(Achievement.order, Achievement.id).all()
    )
    earned_at_by_id = {
        row.achievement_id: row.earned_at
        for row in db.query(UserAchievement).filter(UserAchievement.user_id == user.id).all()
    }

    # Each condition_type's current value only needs computing once, no
    # matter how many achievements of that type exist.
    value_cache: dict[str, int] = {}

    def current_value(condition_type: str) -> int:
        if condition_type not in value_cache:
            compute = CONDITION_TYPES.get(condition_type)
            value_cache[condition_type] = compute(db, user) if compute else 0
        return value_cache[condition_type]

    result = []
    for a in achievements:
        earned = a.id in earned_at_by_id
        is_hidden = a.visibility == VISIBILITY_HIDDEN

        if not earned and is_hidden and not a.show_before_unlock:
            # Fully invisible until earned -- omitted entirely, not just
            # styled as locked, so it can't be discovered early.
            continue

        if not earned and is_hidden:
            # Visible as a locked mystery tile: the real icon (the client
            # dims it), but the condition itself stays withheld.
            result.append(
                UserAchievementOut(
                    id=a.id,
                    title=None,
                    description=None,
                    icon_url=url_for_key(a.icon_key),
                    color=a.color,
                    condition_type=None,
                    condition_value=None,
                    current_value=None,
                    earned=False,
                    earned_at=None,
                )
            )
            continue

        result.append(
            UserAchievementOut(
                id=a.id,
                title=a.title,
                description=a.description,
                icon_url=url_for_key(a.icon_key),
                color=a.color,
                condition_type=a.condition_type,
                condition_value=a.condition_value,
                current_value=current_value(a.condition_type),
                earned=earned,
                earned_at=earned_at_by_id.get(a.id),
            )
        )
    return result


class AchievementsSeenIn(BaseModel):
    ids: list[int]


@router.get("/me/achievements/new", response_model=list[UserAchievementOut])
def get_my_new_achievements(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Earned achievements this account hasn't been shown yet -- the app
    celebrates these (on opening, after a lesson, in Профиль) and then
    marks them seen, so each one is celebrated exactly once per account,
    whatever device or login. Grants anything already due first."""
    grant_all_due_achievements(db, user)
    db.commit()
    unseen = {
        row[0]
        for row in db.query(UserAchievement.achievement_id)
        .filter(UserAchievement.user_id == user.id, UserAchievement.seen_at.is_(None))
        .all()
    }
    if not unseen:
        return []
    return [a for a in get_my_achievements(db, user) if a.id in unseen and a.earned]


@router.post("/me/achievements/seen", status_code=status.HTTP_204_NO_CONTENT)
def mark_my_achievements_seen(
    payload: AchievementsSeenIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)
):
    """Records that these achievements' celebration was shown."""
    if payload.ids:
        db.query(UserAchievement).filter(
            UserAchievement.user_id == user.id,
            UserAchievement.achievement_id.in_(payload.ids),
            UserAchievement.seen_at.is_(None),
        ).update({UserAchievement.seen_at: utc_now()}, synchronize_session=False)
        db.commit()


@router.get("/me/rating", response_model=UserRatingOut)
def get_my_rating(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Everything the Profile screen's "Рейтинг" block needs in one round
    trip -- current points, current season, current rank (+ the next rank
    up, for a progress bar), and past seasons' frozen results. A fully
    separate system from achievements (see app/rating/): nothing here
    touches Achievement/UserAchievement, and this never recomputes a past
    season's SeasonHistory row from the CURRENT rating -- that snapshot is
    permanent the moment a season ends."""
    # Brings the season schedule up to date first, so "which season is
    # running" is answered from the stored periods rather than from
    # whenever the background sweep last ran (see app/rating/scheduler.py).
    sync_season_states(db)
    refresh_rank_positions()

    rating = get_or_create_user_rating(db, user.id)
    rank = current_rank_for_points(db, rating.total_points)
    next_rank = next_rank_for_points(db, rating.total_points)
    season = get_active_season(db)

    history_rows = (
        db.query(SeasonHistory)
        .filter(SeasonHistory.user_id == user.id)
        .order_by(SeasonHistory.ended_at.desc())
        .all()
    )
    history = [
        SeasonHistoryOut(
            season_id=row.season_id,
            season_name=row.season.name if row.season else "",
            points=row.points,
            rank=rank_public_out(row.rank) if row.rank_id else None,
            ended_at=row.ended_at,
        )
        for row in history_rows
    ]

    return UserRatingOut(
        total_points=rating.total_points,
        season=SeasonOut.model_validate(season, from_attributes=True) if season else None,
        rank=rank_public_out(rank),
        next_rank=rank_public_out(next_rank),
        points_to_next_rank=(next_rank.min_points - rating.total_points) if next_rank else None,
        history=history,
        points_per_learned_word=get_rating_settings(db).points_per_learned_word,
        rank_position=rank_position_for_user(db, rank, rating) if rank else None,
        position_change=position_changes(db, [user.id]).get(user.id) if rank else None,
    )


@router.get("/me/stats")
def get_my_stats(
    days: int = 7,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """The "Статистика" screen in one round trip, all from what is already
    recorded: answers (WordAttempt), active days (UserActivityDay), rating
    points (UserWordPoints + quest rewards), lessons and word scores.
    `days` is the chart's range: 7 or 30, compared with the period before."""
    from collections import Counter, defaultdict

    from sqlalchemy import func as sa_func

    from app.achievements.conditions import words_learned_count
    from app.core.dates import DUSHANBE_TZ
    from app.models.quest import Quest, UserQuestWordDay
    from app.models.rating import UserWordPoints
    from app.models.word import Word
    from app.models.word_attempt import WordAttempt

    days = 30 if days >= 30 else 7
    today = dushanbe_today()
    period_start = today - timedelta(days=days - 1)
    prev_start = period_start - timedelta(days=days)

    def local_day(dt):
        return dt.astimezone(DUSHANBE_TZ).date()

    attempts = (
        db.query(WordAttempt.exercise_key, WordAttempt.is_correct, WordAttempt.duration_ms, WordAttempt.created_at)
        .filter(WordAttempt.user_id == user.id)
        .all()
    )
    total = len(attempts)
    correct = sum(1 for a in attempts if a.is_correct)
    per_ex: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    answers_by_day: Counter = Counter()
    weekday: Counter = Counter()
    durations = []
    week_ms = 0
    week_start = today - timedelta(days=6)
    for a in attempts:
        per_ex[a.exercise_key][1] += 1
        if a.is_correct:
            per_ex[a.exercise_key][0] += 1
        d = local_day(a.created_at)
        answers_by_day[d] += 1
        weekday[d.weekday()] += 1
        if a.duration_ms:
            # More than 2 minutes on one answer is idling, not studying:
            # only the first 2 minutes count.
            ms = min(a.duration_ms, 120_000)
            durations.append(ms)
            if d >= week_start:
                week_ms += ms

    # Points per day: learned words plus quest rewards.
    points_by_day: Counter = Counter()
    for pts, at in db.query(UserWordPoints.points_awarded, UserWordPoints.awarded_at).filter(
        UserWordPoints.user_id == user.id
    ):
        points_by_day[local_day(at)] += pts
    for reward, used in (
        db.query(Quest.reward_points, UserQuestWordDay.used_date)
        .join(Quest, Quest.id == UserQuestWordDay.quest_id)
        .filter(UserQuestWordDay.user_id == user.id)
    ):
        points_by_day[used] += reward
    chart = [
        {"date": (period_start + timedelta(days=i)).isoformat(), "points": points_by_day.get(period_start + timedelta(days=i), 0)}
        for i in range(days)
    ]
    period_total = sum(p["points"] for p in chart)
    prev_total = sum(points_by_day.get(prev_start + timedelta(days=i), 0) for i in range(days))

    # Active days: the last 5 weeks for the calendar, and the best streak ever.
    active_days = sorted(
        r[0] for r in db.query(UserActivityDay.activity_date).filter(UserActivityDay.user_id == user.id)
    )
    best = run = 0
    prev = None
    for d in active_days:
        run = run + 1 if prev is not None and d - prev == timedelta(days=1) else 1
        best = max(best, run)
        prev = d
    cal_start = today - timedelta(days=34)
    active_set = set(active_days)
    calendar = [
        {
            "date": (cal_start + timedelta(days=i)).isoformat(),
            "active": (cal_start + timedelta(days=i)) in active_set,
            "answers": answers_by_day.get(cal_start + timedelta(days=i), 0),
        }
        for i in range(35)
    ]

    # The words answered wrong most often (at least twice).
    wrong_rows = (
        db.query(WordAttempt.word_id, sa_func.count(WordAttempt.id))
        .filter(WordAttempt.user_id == user.id, WordAttempt.is_correct.is_(False))
        .group_by(WordAttempt.word_id)
        .order_by(sa_func.count(WordAttempt.id).desc())
        .limit(5)
        .all()
    )
    words = {w.id: w for w in db.query(Word).filter(Word.id.in_([r[0] for r in wrong_rows]))} if wrong_rows else {}
    hard_words = [
        {"word_id": wid, "word": words[wid].word, "dictionary_id": words[wid].dictionary_id, "mistakes": n}
        for wid, n in wrong_rows
        if n >= 2 and wid in words
    ]

    learned_week = (
        db.query(sa_func.count(UserWordPoints.id))
        .filter(UserWordPoints.user_id == user.id, UserWordPoints.awarded_at >= utc_now() - timedelta(days=7))
        .scalar()
        or 0
    )

    return {
        "accuracy": round(correct * 100 / total) if total else 0,
        "total_answers": total,
        "exercises": [{"exercise_key": k, "correct": c, "total": t} for k, (c, t) in per_ex.items()],
        "range_days": days,
        "points_chart": chart,
        "points_total": period_total,
        "points_prev_total": prev_total,
        "calendar": calendar,
        "current_streak": streak_days_count(db, user),
        # Freezes can make the current streak longer than any plain run.
        "best_streak": max(best, streak_days_count(db, user)),
        "lessons_completed": lessons_completed_count(db, user),
        "words_learned": words_learned_count(db, user),
        "words_learned_week": learned_week,
        "time_minutes": round(sum(durations) / 60000),
        "time_week_minutes": round(week_ms / 60000),
        "avg_answer_seconds": round(sum(durations) / len(durations) / 1000, 1) if durations else None,
        "best_weekday": weekday.most_common(1)[0][0] if weekday else None,
        "hard_words": hard_words,
    }
