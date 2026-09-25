"""Lazily-created singleton rows and band lookups -- same "id=1, created on
first read" idiom as app/rating/service.py's get_rating_settings and
app/word_levels/service.py's level lookups.
"""

from sqlalchemy.orm import Session

from app.models.priority import PriorityLevelBand, PriorityRecencyBand, PriorityStabilityBand, PrioritySettings


def get_priority_settings(db: Session) -> PrioritySettings:
    settings = db.get(PrioritySettings, 1)
    if settings is None:
        settings = PrioritySettings(id=1)
        db.add(settings)
        db.flush()
    return settings


def ordered_recency_bands(db: Session) -> list[PriorityRecencyBand]:
    return (
        db.query(PriorityRecencyBand)
        .filter(PriorityRecencyBand.enabled.is_(True))
        .order_by(PriorityRecencyBand.min_days, PriorityRecencyBand.id)
        .all()
    )


def ordered_stability_bands(db: Session) -> list[PriorityStabilityBand]:
    return (
        db.query(PriorityStabilityBand)
        .filter(PriorityStabilityBand.enabled.is_(True))
        .order_by(PriorityStabilityBand.min_percent, PriorityStabilityBand.id)
        .all()
    )


def ordered_priority_level_bands(db: Session) -> list[PriorityLevelBand]:
    return (
        db.query(PriorityLevelBand)
        .filter(PriorityLevelBand.enabled.is_(True))
        .order_by(PriorityLevelBand.min_score, PriorityLevelBand.id)
        .all()
    )


def recency_band_for_days(bands: list[PriorityRecencyBand], days: int) -> PriorityRecencyBand | None:
    for band in bands:
        if band.min_days <= days and (band.max_days is None or days <= band.max_days):
            return band
    return None


def stability_band_for_percent(bands: list[PriorityStabilityBand], percent: int) -> PriorityStabilityBand | None:
    for band in bands:
        if band.min_percent <= percent <= band.max_percent:
            return band
    return None


def priority_level_band_for_score(bands: list[PriorityLevelBand], score: float) -> PriorityLevelBand | None:
    for band in bands:
        if band.min_score <= score and (band.max_score is None or score <= band.max_score):
            return band
    return None


def priority_role_bands(db: Session) -> dict[str, PriorityLevelBand | None]:
    """Maps the 5 roles the spec assigns real behaviour to (Критический ->
    auto-lesson trigger, Высокий/Средний -> quest word preference,
    Низкий/Минимальный -> distractor pool) onto whichever enabled
    PriorityLevelBand rows currently occupy that RANK by score --
    positionally, exactly like app.word_levels.top_level_threshold treats
    "the top WordLevel", never by matching a literal name (an admin
    renaming a band must never silently disable its behaviour).

    Ranked highest-score-first for "critical"/"high"/"medium", and
    lowest-score-first for "low"/"minimal". With fewer than 5 enabled
    bands some roles legitimately resolve to the same band, or to None if
    there simply aren't enough bands configured yet -- every call site
    already treats None as "nothing qualifies for this role right now"."""
    bands = sorted(ordered_priority_level_bands(db), key=lambda b: -b.min_score)

    def at(index: int) -> PriorityLevelBand | None:
        try:
            return bands[index]
        except IndexError:
            return None

    return {
        "critical": at(0),
        "high": at(1),
        "medium": at(2),
        "low": at(-2) if len(bands) >= 2 else None,
        "minimal": at(-1) if bands else None,
    }
