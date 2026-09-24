"""Admin Web's "Рейтинг" section: rating-points settings, Rank definitions
(with uploaded icons), and Seasons -- entirely separate from
admin_achievements.py, sharing only the same conventions (multipart
Form+File create/update, a dedicated reorder endpoint, block-delete-if-
referenced), never any model or table.
"""

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.core.dates import as_utc, utc_now
from app.core.deps import get_current_admin
from app.core.storage import delete_by_key, save_upload, url_for_key
from app.database import get_db
from app.models.rating import SEASON_COMPLETED, SEASON_SCHEDULED, Rank, Season, SeasonHistory
from app.models.user import User
from app.rating import (
    assert_rank_range_free,
    assert_season_period_free,
    end_season,
    get_or_create_user_rating,
    get_rating_settings,
    grant_rating_points,
    sync_season_states,
)
from app.schemas.rating import (
    GrantRatingPointsIn,
    RankOut,
    RatingSettingsIn,
    RatingSettingsOut,
    ReorderRanksIn,
    SeasonCreateIn,
    SeasonOut,
    SeasonUpdateIn,
    UserPointsOut,
)

router = APIRouter(prefix="/admin/rating", tags=["admin-rating"])

MAX_ICON_BYTES = 5 * 1024 * 1024
ALLOWED_ICON_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp"}


def _rank_out(r: Rank) -> RankOut:
    return RankOut(
        id=r.id,
        name=r.name,
        min_points=r.min_points,
        max_points=r.max_points,
        icon_url=url_for_key(r.icon_key),
        color=r.color,
        order=r.order,
        enabled=r.enabled,
    )


def _read_validated_icon(icon: UploadFile) -> None:
    if icon.content_type not in ALLOWED_ICON_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Допустимые форматы: JPEG, PNG, WEBP"
        )
    data = icon.file.read()
    if len(data) > MAX_ICON_BYTES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Файл слишком большой (максимум 5 МБ)"
        )
    if len(data) == 0:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Пустой файл")
    icon.file.seek(0)


# --- Настройки очков и сезонного сброса -------------------------------------


@router.get("/settings", response_model=RatingSettingsOut)
def get_settings(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    settings = get_rating_settings(db)
    return RatingSettingsOut(
        points_per_learned_word=settings.points_per_learned_word,
        season_reset_mode=settings.season_reset_mode,
        season_reset_value=settings.season_reset_value,
    )


@router.put("/settings", response_model=RatingSettingsOut)
def update_settings(payload: RatingSettingsIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Changing `points_per_learned_word` only ever affects future awards
    -- see app/rating/service.py's award_word_points_if_new, which
    snapshots the value onto UserWordPoints at award time. Already-earned
    points are never recalculated."""
    settings = get_rating_settings(db)
    settings.points_per_learned_word = payload.points_per_learned_word
    settings.season_reset_mode = payload.season_reset_mode
    settings.season_reset_value = payload.season_reset_value
    db.commit()
    return RatingSettingsOut(
        points_per_learned_word=settings.points_per_learned_word,
        season_reset_mode=settings.season_reset_mode,
        season_reset_value=settings.season_reset_value,
    )


# --- Ранги -------------------------------------------------------------------


@router.get("/ranks", response_model=list[RankOut])
def list_ranks(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    ranks = db.query(Rank).order_by(Rank.order, Rank.id).all()
    return [_rank_out(r) for r in ranks]


@router.post("/ranks", response_model=RankOut, status_code=status.HTTP_201_CREATED)
def create_rank(
    name: str = Form(..., min_length=1, max_length=100),
    min_points: int = Form(..., ge=0),
    max_points: int | None = Form(None),
    color: str = Form("#6366F1"),
    order: int = Form(0),
    enabled: bool = Form(True),
    icon: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    if max_points is not None and max_points < min_points:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Верхняя граница меньше нижней"
        )
    try:
        assert_rank_range_free(db, min_points=min_points, max_points=max_points, enabled=enabled)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e))

    icon_key = None
    if icon is not None and icon.filename:
        _read_validated_icon(icon)
        icon_key = save_upload(icon, subdir="ranks/icons")

    rank = Rank(
        name=name.strip(),
        min_points=min_points,
        max_points=max_points,
        icon_key=icon_key,
        color=color,
        order=order,
        enabled=enabled,
    )
    db.add(rank)
    db.commit()
    db.refresh(rank)
    return _rank_out(rank)


def _get_rank_or_404(db: Session, rank_id: int) -> Rank:
    rank = db.get(Rank, rank_id)
    if rank is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Rank not found")
    return rank


@router.patch("/ranks/{rank_id}", response_model=RankOut)
def update_rank(
    rank_id: int,
    name: str | None = Form(None, min_length=1, max_length=100),
    min_points: int | None = Form(None, ge=0),
    max_points: int | None = Form(None),
    clear_max_points: bool = Form(False),
    color: str | None = Form(None),
    order: int | None = Form(None),
    enabled: bool | None = Form(None),
    icon: UploadFile | None = File(None),
    remove_icon: bool = Form(False),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Updates this SAME row in place -- editing a rank's name/range/icon/
    color never affects the frozen SeasonHistory rows that already
    reference it (see app/models/rating.py's SeasonHistory docstring)."""
    rank = _get_rank_or_404(db, rank_id)

    new_min = min_points if min_points is not None else rank.min_points
    if clear_max_points:
        new_max = None
    elif max_points is not None:
        new_max = max_points
    else:
        new_max = rank.max_points
    new_enabled = enabled if enabled is not None else rank.enabled

    if new_max is not None and new_max < new_min:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Верхняя граница меньше нижней"
        )
    try:
        assert_rank_range_free(db, min_points=new_min, max_points=new_max, enabled=new_enabled, exclude_id=rank.id)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e))

    if name is not None:
        rank.name = name.strip()
    rank.min_points = new_min
    rank.max_points = new_max
    if color is not None:
        rank.color = color
    if order is not None:
        rank.order = order
    rank.enabled = new_enabled

    has_new_icon = icon is not None and icon.filename
    if has_new_icon:
        _read_validated_icon(icon)
        old_key = rank.icon_key
        rank.icon_key = save_upload(icon, subdir="ranks/icons")
        delete_by_key(old_key)
    elif remove_icon:
        delete_by_key(rank.icon_key)
        rank.icon_key = None

    db.commit()
    db.refresh(rank)
    return _rank_out(rank)


@router.put("/ranks/order", response_model=list[RankOut])
def reorder_ranks(payload: ReorderRanksIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    ranks = db.query(Rank).filter(Rank.id.in_(payload.rank_ids)).all()
    by_id = {r.id: r for r in ranks}
    missing = [i for i in payload.rank_ids if i not in by_id]
    if missing:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Unknown rank ids: {missing}")

    for position, rank_id in enumerate(payload.rank_ids):
        by_id[rank_id].order = position
    db.commit()

    ordered = db.query(Rank).order_by(Rank.order, Rank.id).all()
    return [_rank_out(r) for r in ordered]


@router.delete("/ranks/{rank_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_rank(rank_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Refuses to delete a rank any completed season's history points to
    -- disable it instead. A past season's "you reached Platinum" result
    must never be left dangling or silently rewritten."""
    rank = _get_rank_or_404(db, rank_id)
    referenced = (
        db.query(SeasonHistory).filter(SeasonHistory.rank_id == rank_id).first() is not None
    )
    if referenced:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Этот ранг уже зафиксирован в истории сезонов -- отключите его вместо удаления",
        )
    icon_key = rank.icon_key
    db.delete(rank)
    db.commit()
    delete_by_key(icon_key)


# --- Сезоны ------------------------------------------------------------------


def _season_out(s: Season) -> SeasonOut:
    return SeasonOut(
        id=s.id,
        name=s.name,
        starts_at=s.starts_at,
        ends_at=s.ends_at,
        ended_at=s.ended_at,
        status=s.status,
        icon_url=url_for_key(s.icon_key),
    )


def _get_season_or_404(db: Session, season_id: int) -> Season:
    season = db.get(Season, season_id)
    if season is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Season not found")
    return season


@router.get("/seasons", response_model=list[SeasonOut])
def list_seasons(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Brings the schedule up to date before listing it, so the admin can
    never be looking at a season the stored period says has already ended
    or already begun -- the background sweep does the same thing on its own
    clock, this just makes the page never lag behind it."""
    sync_season_states(db)
    seasons = db.query(Season).order_by(Season.starts_at.desc(), Season.id.desc()).all()
    return [_season_out(s) for s in seasons]


@router.post("/seasons", response_model=SeasonOut, status_code=status.HTTP_201_CREATED)
def create_season(payload: SeasonCreateIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Creates a season for a period. Several may be queued up in advance
    as long as their periods don't collide -- and a period that begins
    exactly when another ends is NOT a collision (see
    assert_season_period_free).

    Always created as `scheduled`: whether it should actually be live is
    decided by sync_season_states alone, from the stored period, so there
    is only ever one implementation of "which season is active".
    """
    sync_season_states(db)
    starts_at = as_utc(payload.starts_at) if payload.starts_at else utc_now()
    ends_at = as_utc(payload.ends_at) if payload.ends_at else None
    try:
        assert_season_period_free(db, starts_at=starts_at, ends_at=ends_at)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(e))

    season = Season(name=payload.name.strip(), starts_at=starts_at, ends_at=ends_at, status=SEASON_SCHEDULED)
    db.add(season)
    db.commit()
    sync_season_states(db)
    db.refresh(season)
    return _season_out(season)


@router.patch("/seasons/{season_id}", response_model=SeasonOut)
def update_season(
    season_id: int,
    payload: SeasonUpdateIn,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Edits a season's name or period. A COMPLETED season is refused
    outright: its result is already frozen into SeasonHistory, and moving
    its period afterwards would make that history describe a period the
    season no longer claims to have had.

    Giving the ACTIVE season an `ends_at` is the normal way to unblock
    scheduling the next one -- and if that moment is already in the past,
    the sync below ends it right here, exactly as the scheduler would."""
    season = _get_season_or_404(db, season_id)
    if season.status == SEASON_COMPLETED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Завершённый сезон нельзя изменить -- его результат уже в истории",
        )

    starts_at = as_utc(payload.starts_at) if payload.starts_at else season.starts_at
    if payload.clear_ends_at:
        ends_at = None
    elif payload.ends_at is not None:
        ends_at = as_utc(payload.ends_at)
    else:
        ends_at = season.ends_at

    try:
        assert_season_period_free(db, starts_at=starts_at, ends_at=ends_at, exclude_id=season.id)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(e))

    if payload.name is not None:
        season.name = payload.name.strip()
    season.starts_at = starts_at
    season.ends_at = ends_at
    db.commit()
    sync_season_states(db)
    db.refresh(season)
    return _season_out(season)


@router.delete("/seasons/{season_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_season(season_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Only a SCHEDULED season can be deleted -- one that never ran and so
    left nothing behind. An active season must be ended (that is what
    writes its history), and a completed one is history."""
    season = _get_season_or_404(db, season_id)
    if season.status != SEASON_SCHEDULED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Удалить можно только запланированный сезон",
        )
    icon_key = season.icon_key
    db.delete(season)
    db.commit()
    delete_by_key(icon_key)


@router.put("/seasons/{season_id}/icon", response_model=SeasonOut)
def set_season_icon(
    season_id: int,
    icon: UploadFile = File(...),
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    """Stores a picture for this season, same validation and storage-key
    convention as a rank icon. Nothing displays it yet -- it is kept so
    the season already has one when something does."""
    season = _get_season_or_404(db, season_id)
    _read_validated_icon(icon)
    new_key = save_upload(icon, subdir="seasons/icons")
    old_key = season.icon_key
    season.icon_key = new_key
    db.commit()
    delete_by_key(old_key)
    db.refresh(season)
    return _season_out(season)


@router.delete("/seasons/{season_id}/icon", response_model=SeasonOut)
def delete_season_icon(season_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    season = _get_season_or_404(db, season_id)
    old_key = season.icon_key
    season.icon_key = None
    db.commit()
    delete_by_key(old_key)
    db.refresh(season)
    return _season_out(season)


@router.post("/seasons/{season_id}/end", response_model=SeasonOut)
def end_season_endpoint(season_id: int, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Ends a season by hand, at any moment, regardless of the period it
    was given -- the manual half of the two ways a season can end. Freezes
    every user's current points/rank into SeasonHistory, then applies the
    configured seasonal reset (see app/rating/service.py's end_season):
    irreversible, and the one rating action that genuinely changes every
    user's data at once.

    The sync afterwards is what makes a hand-off immediate: if the next
    season's start has already arrived, it goes live in the same request
    rather than waiting for the background sweep."""
    season = _get_season_or_404(db, season_id)
    try:
        end_season(db, season)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(e))
    sync_season_states(db)
    db.refresh(season)
    return _season_out(season)


# --- Ручная корректировка очков ---------------------------------------------


@router.post("/users/{user_id}/grant-points", response_model=UserPointsOut)
def grant_points(user_id: int, payload: GrantRatingPointsIn, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Admin-only manual rating adjustment -- reuses grant_rating_points,
    the SAME function Quest rewards already call, never a second way
    points get added. Useful for correcting a mistake, running an event,
    or (as originally added for) seeding realistic test accounts across
    the rank ladder without having to play through hundreds of real
    lessons. `points` is a delta, floored so a large negative adjustment
    can never leave a user below 0."""
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    rating = get_or_create_user_rating(db, user.id)
    grant_rating_points(db, user, payload.points)
    rating.total_points = max(0, rating.total_points)
    db.commit()
    db.refresh(rating)
    return UserPointsOut(user_id=user.id, total_points=rating.total_points)
