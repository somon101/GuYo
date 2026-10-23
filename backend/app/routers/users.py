import re
from datetime import date, timedelta

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.rating.names import season_name
from app.achievements.streak import active_today
from app.core.content_language import reading_language
from app.achievements.conditions import streak_with_freezes
from app.achievements import CONDITION_TYPES, grant_all_due_achievements, lessons_completed_count, streak_days_count, words_learned_count
from app.core.dates import dushanbe_today, utc_now
from app.core.dates import DUSHANBE_TZ, dushanbe_day_start
from app.core.deps import get_current_admin, get_current_user, require_current_app
from app.core.public_id import generate_public_id
from app.core.security import hash_password
from app.core.storage import delete_by_key, save_bytes, url_for_key
from app.database import get_db
from app.models.achievement import VISIBILITY_HIDDEN, Achievement, UserAchievement, UserActivityDay, UserStreakFreeze
from app.models.admin import Admin
from app.models.rating import SeasonHistory
from app.models.user import User
from app.models.lesson import Lesson
from app.models.word_progress import WordProgress
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


def login_taken(db: Session, login: str, except_user_id: int | None = None) -> bool:
    """Case-insensitive: "Somon" is taken if "somon" exists."""
    query = db.query(User.id).filter(func.lower(User.login) == login.strip().lower())
    if except_user_id is not None:
        query = query.filter(User.id != except_user_id)
    return query.first() is not None


def new_user_row(
    db: Session,
    *,
    login: str,
    password: str,
    first_name: str,
    last_name: str,
    # None for an account created without a Google account: signing up does not
    # require one (see RegisterIn.id_token), and the email arrives later if the
    # user connects Google from Settings.
    email: str | None = None,
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
    if login_taken(db, login):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Этот логин уже занят")
    # Only when there IS an email: `== None` matches every account that has none,
    # which would reject the very sign-up this now allows.
    if email is not None and db.query(User).filter(User.email == email).first() is not None:
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


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
def delete_my_account(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Удаление аккаунта из приложения -- требование Google Play.

    Аккаунт помечается удалённым и сразу исчезает отовсюду: рейтинг, друзья,
    поиск, уведомления. Данные остаются 30 дней, чтобы человек мог передумать:
    вход по прежнему логину и паролю возвращает всё. Через 30 дней
    `python -m app.account_deletion purge` удаляет строку окончательно, вместе
    со всеми её данными (все таблицы ссылаются на users с ON DELETE CASCADE).

    Объявлен ДО "/{user_id}": иначе админский маршрут перехватил бы "me" как
    несуществующий номер и ответил бы 403.
    """
    from app.account_deletion import mark_deleted

    old_avatar = user.avatar_key
    mark_deleted(db, user)
    # Фото профиля убираем сразу: это персональные данные, и держать их в
    # общем хранилище до истечения окна незачем.
    if old_avatar:
        user.avatar_key = None
        db.commit()
        delete_by_key(old_avatar)
    return None


class UserPasswordIn(BaseModel):
    password: str


@router.put("/{user_id}/password", status_code=status.HTTP_204_NO_CONTENT)
def set_user_password(
    user_id: int, payload: UserPasswordIn, db: Session = Depends(get_db), _admin: Admin = Depends(get_current_admin)
):
    """Support: the admin sets a new password for a user -- e.g. an account
    made with Google (whose password nobody knows) that has to log in
    with login and password. A Google link, if any, stays."""
    if len(payload.password) < 4:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Минимум 4 символа")
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    user.password_hash = hash_password(payload.password)
    db.commit()


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


class TextCheckUnlimitedIn(BaseModel):
    text_check_unlimited: bool


@router.put("/{user_id}/text-check-unlimited")
def set_text_check_unlimited(
    user_id: int,
    payload: TextCheckUnlimitedIn,
    db: Session = Depends(get_db),
    _admin: Admin = Depends(get_current_admin),
):
    """«Проверка текста» without the daily limit for ONE person (Admin Web's
    «ИИ» -> «Проверка текста» -> пользователи, or the user's own card).

    Deliberately not Premium: this is for a tester or a team member who must
    be able to check texts freely, so it is granted by hand and never sold."""
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    user.text_check_unlimited = payload.text_check_unlimited
    db.commit()
    return {"id": user.id, "text_check_unlimited": user.text_check_unlimited}


def _profile_out(db: Session, user: User) -> UserProfileOut:
    from app.seasonpass.cosmetics import frame_keys, worn

    badge, title = worn(db, user)
    return UserProfileOut(
        badge=badge,
        frame=frame_keys(db, [user.id]).get(user.id),
        title=title,
        id=user.id,
        public_id=user.public_id,
        login=user.login,
        first_name=user.first_name,
        last_name=user.last_name,
        email=user.email,
        avatar_url=url_for_key(user.avatar_key),
        current_streak_days=streak_days_count(db, user),
        streak_active_today=active_today(db, user),
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
        language_unavailable=_unavailable(db, user),
    )


def _unavailable(db: Session, user: User) -> list[str]:
    from app.languages.readiness import unavailable_for

    return unavailable_for(db, user)


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
        "active_today": today in active,
        "today": today.isoformat(),
        "active_dates": [d.isoformat() for d in active],
        # Missed days a weekly freeze covered (see streak_with_freezes).
        "frozen_dates": [d.isoformat() for d in frozen if d >= since],
        # Streak freezes in stock (spent by themselves when a gap would break the streak).
        "freezes": user.streak_freezes or 0,
        "merged_days": user.streak_merge_days or 0,
        "streak_merge_items": user.streak_merge_items or 0,
    }


@router.get("/me/streak/history")
def get_streak_history(
    month: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """A month of the permanent activity calendar, including the day's
    learned-word and completed-lesson progress. Dates use Dushanbe time."""
    if not re.fullmatch(r"\d{4}-\d{2}", month):
        raise HTTPException(status_code=422, detail="Месяц должен быть в формате YYYY-MM")
    try:
        first = date.fromisoformat(f"{month}-01")
    except ValueError:
        raise HTTPException(status_code=422, detail="Некорректный месяц") from None
    next_first = date(first.year + (first.month == 12), 1 if first.month == 12 else first.month + 1, 1)
    last = date.fromordinal(next_first.toordinal() - 1)
    today = dushanbe_today()

    active = {
        row[0] for row in db.query(UserActivityDay.activity_date).filter(
            UserActivityDay.user_id == user.id,
            UserActivityDay.activity_date >= first,
            UserActivityDay.activity_date <= last,
        )
    }
    frozen = {
        row[0] for row in db.query(UserStreakFreeze.covered_date).filter(
            UserStreakFreeze.user_id == user.id,
            UserStreakFreeze.covered_date >= first,
            UserStreakFreeze.covered_date <= last,
        )
    }
    # Include the automatically forgiven days in the currently connected run
    # as frozen markers on the calendar; they remain absent from activity rows.
    _, currently_forgiven = streak_with_freezes(db, user)
    frozen.update(currently_forgiven)
    start_at, end_at = dushanbe_day_start(first), dushanbe_day_start(next_first)
    words: dict[date, int] = {}
    for (at,) in db.query(WordProgress.mastered_at).filter(
        WordProgress.user_id == user.id,
        WordProgress.mastered_at >= start_at,
        WordProgress.mastered_at < end_at,
        WordProgress.mastered_at.is_not(None),
    ):
        day = at.astimezone(DUSHANBE_TZ).date()
        words[day] = words.get(day, 0) + 1
    lessons: dict[date, int] = {}
    for (at,) in db.query(Lesson.completed_at).filter(
        Lesson.user_id == user.id,
        Lesson.completed_by_pass.is_(True),
        Lesson.completed_at >= start_at,
        Lesson.completed_at < end_at,
        Lesson.completed_at.is_not(None),
    ):
        day = at.astimezone(DUSHANBE_TZ).date()
        lessons[day] = lessons.get(day, 0) + 1

    days = []
    active_total = freeze_total = missed_total = 0
    for offset in range((last - first).days + 1):
        day = first + timedelta(days=offset)
        state = "active" if day in active else "frozen" if day in frozen else "future" if day > today else "today" if day == today else "missed"
        active_total += state == "active"
        freeze_total += state == "frozen"
        missed_total += state == "missed"
        days.append({"date": day.isoformat(), "state": state, "words_learned": words.get(day, 0), "lessons_completed": lessons.get(day, 0)})
    current, _ = streak_with_freezes(db, user)
    return {
        "month": month,
        "current_streak_days": current,
        "merged_days": user.streak_merge_days or 0,
        "streak_merge_items": user.streak_merge_items or 0,
        "active_days": active_total,
        "frozen_days": freeze_total,
        "missed_days": missed_total,
        "days": days,
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
        if login_taken(db, login, except_user_id=user.id):
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Этот логин уже занят")
        user.login = login

    # The email is the linked Google account's and can't be changed here.
    if "email" in fields and fields["email"] != user.email:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Почту изменить нельзя: она привязана к Google")

    if "first_name" in fields:
        user.first_name = fields["first_name"].strip() if fields["first_name"] else None
    if "last_name" in fields:
        user.last_name = fields["last_name"].strip() if fields["last_name"] else None
    # Запоминаем прежние языки ДО правки: они нужны, если новый выбор столкнётся
    # с другим языком пары.
    previous_native = user.translation_language
    previous_learning = user.learning_language

    from app.languages.readiness import KIND_LEARN, KIND_NATIVE, require_published

    if fields.get("translation_language") and fields["translation_language"] != user.translation_language:
        require_published(db, fields["translation_language"], KIND_NATIVE)
    if "learning_language" in fields and fields["learning_language"] != user.learning_language:
        require_published(db, fields["learning_language"], KIND_LEARN)
    if fields.get("translation_language"):
        user.translation_language = fields["translation_language"]
    if fields.get("ui_language"):
        user.ui_language = fields["ui_language"]
    # Язык, который человек изучает. Пара «родной -> изучаемый» решает, что он
    # видит: ответ -- из языковой записи изучаемого языка, подсказка -- из записи
    # родного. Пусто (None) = язык словаря.
    if "learning_language" in fields:
        user.learning_language = fields["learning_language"]

    # Родной и изучаемый не могут совпадать: подсказка была бы на том же языке,
    # что и ответ. Приложение такой вариант не предлагает; если он всё-таки
    # пришёл -- языки МЕНЯЮТСЯ МЕСТАМИ, потому что человек сменил один на
    # другой, а не попросил ошибку.
    if user.learning_language is not None and user.learning_language == user.translation_language:
        changed_learning = "learning_language" in fields
        changed_native = bool(fields.get("translation_language"))
        if changed_learning and previous_learning and previous_learning != user.translation_language:
            user.translation_language = previous_learning
        elif changed_native and previous_native != previous_learning:
            user.learning_language = previous_native
        elif user.learning_language == "ru":
            user.translation_language = "tg"
        else:
            user.translation_language = "ru"

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
    """Every enabled achievement -- plus archived (disabled) ones this user
    already earned, which stay theirs -- each with this user's own earned status
    and (for the ones not yet earned) their current progress -- computed
    fresh here, on read, so it's always accurate even if the user earned
    something through an action that hasn't explicitly re-run the granting
    check (see app/achievements/service.py) since. The backend decides all
    of this; nothing about "have I earned this" is computed in Flutter."""
    earned_at_by_id = {
        row.achievement_id: row.earned_at
        for row in db.query(UserAchievement).filter(UserAchievement.user_id == user.id).all()
    }
    achievements = [
        a
        for a in db.query(Achievement).order_by(Achievement.order, Achievement.id).all()
        if a.enabled or a.id in earned_at_by_id
    ]

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
                title=a.localized(user.ui_language)[0],
                description=a.localized(user.ui_language)[1],
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
            season_name=season_name(row.season) if row.season else "",
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
    covered = {
        r[0] for r in db.query(UserStreakFreeze.covered_date).filter(UserStreakFreeze.user_id == user.id)
    }
    best = run = 0
    prev = None
    for d in active_days:
        # A gap made only of freeze-covered days keeps the run going.
        bridged = prev is not None and all(prev + timedelta(days=i) in covered for i in range(1, (d - prev).days))
        run = run + 1 if prev is not None and bridged else 1
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
