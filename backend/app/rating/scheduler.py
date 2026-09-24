"""Keeps season statuses in step with their stored periods while the
backend is running.

This is a clock, not a source of truth. Every decision it can possibly
make already lives in the `seasons` table -- app/rating/service.py's
`sync_season_states` reads that table, compares the periods against now,
and applies whatever is due. So a backend that was stopped for a week
misses nothing: the first sweep after startup ends the season whose
`ends_at` passed while it was down (recording that scheduled moment, not
the restart moment) and activates whichever season should be live now.

Deliberately an asyncio task rather than a new scheduling dependency:
there is exactly one periodic job in this whole service, it holds no state
of its own, and skipping a tick costs nothing because the next one
recomputes the same thing from scratch.
"""

import asyncio
import logging

from app.database import SessionLocal
from app.rating import sync_season_states

logger = logging.getLogger(__name__)

# A season boundary is a wall-clock moment an admin picked, so a minute of
# lag is invisible in practice. The read paths that actually matter (the
# admin's own season list, and GET /users/me/rating) sync on their own
# anyway, so this loop is the safety net rather than the mechanism.
SEASON_SYNC_INTERVAL_SECONDS = 60


def sync_once() -> bool:
    """One sweep in its own session. Never raises: a failed sweep must not
    kill the loop, because the next one would have fixed the same thing."""
    db = SessionLocal()
    try:
        return sync_season_states(db)
    except Exception:
        logger.exception("season sync failed")
        db.rollback()
        return False
    finally:
        db.close()


async def run_season_scheduler() -> None:
    """Sweeps once immediately (catching up on everything missed while the
    process was down), then every SEASON_SYNC_INTERVAL_SECONDS until
    cancelled at shutdown."""
    while True:
        if await asyncio.to_thread(sync_once):
            logger.info("season states updated")
        await asyncio.sleep(SEASON_SYNC_INTERVAL_SECONDS)
