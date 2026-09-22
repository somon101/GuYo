"""Seasonal rating's own service layer -- entirely separate from
app/achievements/. Nothing here reads or writes Achievement/UserAchievement,
and nothing in app/achievements/ reads or writes any model imported below.
"""

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dates import utc_today
from app.models.rating import (
    RESET_MODE_FIXED,
    SEASON_ACTIVE,
    SEASON_COMPLETED,
    Rank,
    RatingSettings,
    Season,
    SeasonHistory,
    UserRating,
    UserWordPoints,
)
from app.models.user import User


def get_rating_settings(db: Session) -> RatingSettings:
    """Same "single row, always id=1" idiom as LearningSettings -- created
    lazily with defaults on first read rather than requiring a migration
    data-seed."""
    settings = db.get(RatingSettings, 1)
    if settings is None:
        settings = RatingSettings(id=1)
        db.add(settings)
        db.flush()
    return settings


def get_or_create_user_rating(db: Session, user_id: int) -> UserRating:
    rating = db.query(UserRating).filter(UserRating.user_id == user_id).first()
    if rating is None:
        rating = UserRating(user_id=user_id, total_points=0)
        db.add(rating)
        db.flush()
    return rating


def grant_rating_points(db: Session, user: User, points: int) -> None:
    """The one other place (besides award_word_points_if_new) rating
    points ever get added -- used by the Quest system's own reward on
    successful completion (see app/quests/service.py). Deliberately NOT
    deduplicated the way word-points are (no "once per X" ledger here):
    a quest's daily one-word-per-day limit is enforced entirely on the
    Quest side (UserQuestWordDay), not by this generic grant function,
    which just applies whatever point delta it's given."""
    rating = get_or_create_user_rating(db, user.id)
    rating.total_points += points
    db.flush()


def ordered_enabled_ranks(db: Session) -> list[Rank]:
    """Every enabled rank, in the admin's own `order` (then `id` as a
    stable tie-break) -- the one ladder both `current_rank_for_points`
    (fetch once, reuse per lookup) and the "Все уровни" full-ladder screen
    (app/routers/rating.py's GET /rating/ranks) read from, so the two can
    never disagree about how many ranks there are or what order they're
    in."""
    return db.query(Rank).filter(Rank.enabled.is_(True)).order_by(Rank.order, Rank.id).all()


def current_rank_for_points(db: Session, points: int) -> Rank | None:
    """The one place a user's rank is ever determined -- purely a
    comparison against enabled Ranks' own [min_points, max_points] ranges,
    never a stored/cached value that could drift from `points`. Returns
    None (rather than raising) if no enabled rank's range covers `points`,
    e.g. a gap left by admin misconfiguration -- the UI shows a neutral
    "no rank yet" state instead of breaking.

    assert_rank_range_free already refuses to let two enabled ranks'
    ranges overlap, so ordered_enabled_ranks's ordering is normally never
    actually decisive here, but it gives a defined, non-arbitrary answer
    rather than "whatever order the database happened to return" if a
    conflict ever slips through (e.g. a row edited directly outside the
    API)."""
    for rank in ordered_enabled_ranks(db):
        if rank.min_points <= points and (rank.max_points is None or points <= rank.max_points):
            return rank
    return None


def next_rank_for_points(db: Session, points: int) -> Rank | None:
    """The lowest-`min_points` enabled rank still above the user's current
    points -- what a progress-to-next-rank bar climbs toward. None if the
    user is already at (or above) the highest enabled rank."""
    return (
        db.query(Rank)
        .filter(Rank.enabled.is_(True), Rank.min_points > points)
        .order_by(Rank.min_points.asc())
        .first()
    )


def ranks_overlap(a_min: int, a_max: int | None, b_min: int, b_max: int | None) -> bool:
    a_hi = a_max if a_max is not None else float("inf")
    b_hi = b_max if b_max is not None else float("inf")
    return a_min <= b_hi and b_min <= a_hi


def assert_rank_range_free(
    db: Session, *, min_points: int, max_points: int | None, enabled: bool, exclude_id: int | None = None
) -> None:
    """Raises ValueError if an enabled rank with this range would overlap
    another already-enabled rank's range. A disabled rank is never
    checked -- it plays no part in current_rank_for_points, so its range
    can't actually conflict with anything live."""
    if not enabled:
        return
    query = db.query(Rank).filter(Rank.enabled.is_(True))
    if exclude_id is not None:
        query = query.filter(Rank.id != exclude_id)
    for other in query.all():
        if ranks_overlap(min_points, max_points, other.min_points, other.max_points):
            raise ValueError(f"Диапазон пересекается с рангом «{other.name}»")


def award_word_points_if_new(db: Session, user: User, word_id: int) -> None:
    """Grants this user rating points for `word_id` at most once, ever --
    the UserWordPoints unique constraint is what actually guarantees that
    at the database level. Safe to call every time a word's `is_learned`
    check passes (the same "safe to call defensively/often" contract
    app/achievements/service.py's check_and_grant_achievements already
    uses): a word that was already awarded is simply skipped, so this
    never double-counts no matter how many times it's called for the same
    (user, word).

    `points_awarded` snapshots RatingSettings.points_per_learned_word at
    this exact moment -- a later admin change to that setting only ever
    affects future awards, never this one.

    The pre-check below narrows the common case, but two truly
    simultaneous requests for the same (user, word) could both pass it --
    the UNIQUE(user_id, word_id) constraint is what actually decides that
    at the database level. The insert runs in its own SAVEPOINT so a
    losing request's IntegrityError only rolls back this one insert (not
    the rest of the caller's transaction, e.g. the WordProgress update
    already made in the same request) and returns quietly, exactly as if
    this word had already been awarded -- never a 500 for the loser, and
    never double-counted points either way."""
    already_awarded = (
        db.query(UserWordPoints).filter(UserWordPoints.user_id == user.id, UserWordPoints.word_id == word_id).first()
        is not None
    )
    if already_awarded:
        return

    settings = get_rating_settings(db)
    points = settings.points_per_learned_word

    try:
        with db.begin_nested():
            db.add(UserWordPoints(user_id=user.id, word_id=word_id, points_awarded=points))
            db.flush()
    except IntegrityError:
        return

    rating = get_or_create_user_rating(db, user.id)
    rating.total_points += points
    db.flush()


LEADERBOARD_LIMIT = 100


def leaderboard_for_rank(db: Session, rank: Rank, limit: int = LEADERBOARD_LIMIT) -> list[UserRating]:
    """Top `limit` users whose CURRENT points fall inside this one rank's
    own range -- never a manually-picked rank, always the caller's own
    (see app/routers/rating.py). Filters directly on UserRating.total_points
    rather than computing every user's rank in Python, since a rank's
    range already says exactly which point values belong to it."""
    query = db.query(UserRating).filter(UserRating.total_points >= rank.min_points)
    if rank.max_points is not None:
        query = query.filter(UserRating.total_points <= rank.max_points)
    return query.order_by(UserRating.total_points.desc(), UserRating.user_id.asc()).limit(limit).all()


def leaderboard_global(db: Session, limit: int = LEADERBOARD_LIMIT) -> list[UserRating]:
    """Top `limit` users across every rank combined, by points alone."""
    return db.query(UserRating).order_by(UserRating.total_points.desc(), UserRating.user_id.asc()).limit(limit).all()


def get_active_season(db: Session) -> Season | None:
    return db.query(Season).filter(Season.status == SEASON_ACTIVE).first()


def apply_season_reset(points: int, settings: RatingSettings) -> int:
    """Never negative -- 0 is the floor regardless of reset mode or how
    large the configured reset value is."""
    if settings.season_reset_mode == RESET_MODE_FIXED:
        new_points = points - settings.season_reset_value
    else:
        new_points = points - round(points * settings.season_reset_value / 100)
    return max(0, new_points)


def end_season(db: Session, season: Season) -> None:
    """The one moment a season's result becomes permanent history and
    every user's current points get reset for the next one. Freezes
    EVERY user's points/rank into SeasonHistory (even users with 0
    points, for a complete record) before touching a single
    UserRating.total_points, so a crash partway through never leaves a
    user's history missing while their points are already reset -- both
    happen in the same transaction, committed once at the end."""
    if season.status != SEASON_ACTIVE:
        raise ValueError("Сезон уже завершён")

    settings = get_rating_settings(db)
    user_ids = [row[0] for row in db.query(User.id).all()]

    for user_id in user_ids:
        rating = get_or_create_user_rating(db, user_id)
        rank = current_rank_for_points(db, rating.total_points)
        db.add(
            SeasonHistory(
                user_id=user_id,
                season_id=season.id,
                points=rating.total_points,
                rank_id=rank.id if rank else None,
            )
        )
        rating.total_points = apply_season_reset(rating.total_points, settings)

    season.status = SEASON_COMPLETED
    season.end_date = utc_today()
    db.commit()
