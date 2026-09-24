"""Picking the greeting slogan a user sees today.

One rule, in one place: a user gets a random enabled slogan, that choice
is written down for the day, and the same choice is returned for the rest
of that day. A new day brings a new draw.
"""

import random
from datetime import timedelta

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dates import dushanbe_today
from app.models.slogan import Slogan, UserDailySlogan
from app.models.user import User


def enabled_slogans(db: Session) -> list[Slogan]:
    """Every slogan an admin has left switched on, in their own order --
    the one pool a pick is ever drawn from."""
    return db.query(Slogan).filter(Slogan.enabled.is_(True)).order_by(Slogan.order, Slogan.id).all()


def slogan_for_today(db: Session, user: User) -> Slogan | None:
    """This user's slogan for today, drawn once and then held.

    Returns None only when an admin has no enabled slogans at all, which
    is a real state and not an error -- the client falls back to its own
    built-in line rather than showing an empty greeting.

    Two cases deliberately re-draw rather than reuse yesterday's answer:
      - there is no pick for today yet (the ordinary "new day" case);
      - today's pick points at a slogan that has since been switched off,
        because an admin disabling a line means they no longer want it
        shown, including to whoever already drew it today.
    A pick whose slogan was DELETED disappears with it (the foreign key
    cascades), which lands in the first case.

    "Today" is the server's own Asia/Dushanbe date -- the same day
    boundary quests already reset on, so the app never holds two different
    ideas of when a new day starts.
    """
    today = dushanbe_today()

    pinned = (
        db.query(UserDailySlogan)
        .filter(UserDailySlogan.user_id == user.id, UserDailySlogan.shown_date == today)
        .first()
    )
    if pinned is not None:
        slogan = db.get(Slogan, pinned.slogan_id)
        if slogan is not None and slogan.enabled:
            return slogan
        # Switched off since the draw -- fall through and pick again,
        # replacing the stale pin below.

    pool = enabled_slogans(db)
    if not pool:
        return None

    # "a different one tomorrow": yesterday's line is taken out of the draw
    # whenever there is anything else to give, so two days running never
    # show the same words. With a single enabled slogan there is nothing to
    # swap to and it simply repeats -- an admin's choice, not a bug.
    if len(pool) > 1:
        yesterday = (
            db.query(UserDailySlogan.slogan_id)
            .filter(
                UserDailySlogan.user_id == user.id,
                UserDailySlogan.shown_date == today - timedelta(days=1),
            )
            .scalar()
        )
        if yesterday is not None:
            fresh = [s for s in pool if s.id != yesterday]
            if fresh:
                pool = fresh

    chosen = random.choice(pool)

    if pinned is not None:
        pinned.slogan_id = chosen.id
        db.flush()
        return chosen

    # Two requests from the same user can arrive together on the first
    # load of a new day; UNIQUE(user_id, shown_date) decides which one
    # wins, and the loser simply reads the winner's pick. The insert runs
    # in its own SAVEPOINT so that loss doesn't roll back anything else
    # the caller is doing -- same pattern as award_word_points_if_new.
    try:
        with db.begin_nested():
            db.add(UserDailySlogan(user_id=user.id, slogan_id=chosen.id, shown_date=today))
            db.flush()
    except IntegrityError:
        existing = (
            db.query(UserDailySlogan)
            .filter(UserDailySlogan.user_id == user.id, UserDailySlogan.shown_date == today)
            .first()
        )
        if existing is not None:
            winner = db.get(Slogan, existing.slogan_id)
            if winner is not None and winner.enabled:
                return winner
    return chosen
