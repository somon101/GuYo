"""User-facing rating leaderboards -- entirely read-only, entirely
backend-decided. A user is never able to pick which rank's leaderboard
they see (see /rating/leaderboard below): it's always exactly their own
CURRENT rank, recomputed live from their own points on every call, same
as everywhere else this project determines a rank."""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.core.storage import url_for_key
from app.database import get_db
from app.models.rating import UserRating
from app.models.user import User
from app.rating import current_rank_for_points, get_or_create_user_rating, leaderboard_for_rank, leaderboard_global
from app.schemas.rating import LeaderboardEntryOut, LeaderboardOut, RankPublicOut, rank_public_out

router = APIRouter(prefix="/rating", tags=["rating"])


def _entries_out(db: Session, ratings: list[UserRating], me: User, with_rank: bool) -> list[LeaderboardEntryOut]:
    user_ids = [r.user_id for r in ratings]
    users = {u.id: u for u in db.query(User).filter(User.id.in_(user_ids)).all()}

    # Every rank fetched once, not per row -- current_rank_for_points
    # itself queries the DB, and a global board can be up to 100 rows.
    ranks_cache: dict[int, RankPublicOut | None] = {}

    def rank_for(points: int) -> RankPublicOut | None:
        if not with_rank:
            return None
        if points not in ranks_cache:
            ranks_cache[points] = rank_public_out(current_rank_for_points(db, points))
        return ranks_cache[points]

    entries = []
    for position, rating in enumerate(ratings, start=1):
        user = users.get(rating.user_id)
        if user is None:
            continue
        entries.append(
            LeaderboardEntryOut(
                position=position,
                user_id=user.id,
                login=user.login,
                avatar_url=url_for_key(user.avatar_key),
                total_points=rating.total_points,
                rank=rank_for(rating.total_points),
                is_me=user.id == me.id,
            )
        )
    return entries


@router.get("/leaderboard", response_model=LeaderboardOut)
def get_my_rank_leaderboard(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Top 100 users sharing the CALLER's own current rank -- never a
    rank the user picks. Empty (with `rank: null`) if the user doesn't
    currently fall into any enabled rank's range."""
    my_rating = get_or_create_user_rating(db, user.id)
    my_rank = current_rank_for_points(db, my_rating.total_points)
    if my_rank is None:
        return LeaderboardOut(rank=None, entries=[])

    ratings = leaderboard_for_rank(db, my_rank)
    return LeaderboardOut(rank=rank_public_out(my_rank), entries=_entries_out(db, ratings, user, with_rank=False))


@router.get("/leaderboard/global", response_model=LeaderboardOut)
def get_global_leaderboard(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Top 100 users across every rank combined, sorted purely by points."""
    ratings = leaderboard_global(db)
    return LeaderboardOut(rank=None, entries=_entries_out(db, ratings, user, with_rank=True))
