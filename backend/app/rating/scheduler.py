"""Keeps season statuses in step with their stored periods while the
backend is running.

This is a clock, not a source of truth. Every decision it can possibly
make already lives in the `seasons` table -- app/rating/service.py's
`sync_season_states` reads that table, compares the periods against now,
and applies whatever is due. So a backend that was stopped for a week
misses nothing: the first sweep after startup ends the season whose
`ends_at` passed while it was down (recording that scheduled moment, not
the restart moment) and activates whichever season should be live now.

The same tick also recomputes everyone's place within their rank
(app/rating/movement.py), because a place changes whenever SOMEONE ELSE
earns points and the "you moved N places" notifications can't wait for
the user to open Рейтинг.

Deliberately an asyncio task rather than a new scheduling dependency:
both sweeps hold no state of their own, and skipping a tick costs nothing
because the next one recomputes the same thing from scratch.
"""

import asyncio
import logging
import time

from app.database import SessionLocal
from app.notifications.reminders import run_reminders_once
from app.memory.service import rebuild_pending_memories
from app.rating import refresh_rank_positions, sync_season_states

logger = logging.getLogger(__name__)

# A season boundary is a wall-clock moment an admin picked, so a minute of
# lag is invisible in practice. The read paths that actually matter (the
# admin's own season list, and GET /users/me/rating) sync on their own
# anyway, so this loop is the safety net rather than the mechanism.
SEASON_SYNC_INTERVAL_SECONDS = 60
# Reminders are decided per hour and deduplicated, so a few minutes of
# lag is invisible and the sweep need not run every minute.
REMINDER_INTERVAL_SECONDS = 300


def backfill_memory_once() -> None:
    """Models answer history recorded before the memory model existed, one
    batch per tick, until nothing is left. Never raises."""
    db = SessionLocal()
    try:
        done = rebuild_pending_memories(db)
        if done:
            logger.info("memory model: rebuilt %s pairs", done)
    except Exception:
        logger.exception("memory backfill failed")
        db.rollback()
    finally:
        db.close()


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
    last_reminders = 0.0
    while True:
        if await asyncio.to_thread(sync_once):
            logger.info("season states updated")
        # Places move when OTHER people earn points, so this can't wait
        # for anyone to open Рейтинг -- the notifications depend on it.
        await asyncio.to_thread(refresh_rank_positions, force=True)
        if time.monotonic() - last_reminders >= REMINDER_INTERVAL_SECONDS:
            last_reminders = time.monotonic()
            await asyncio.to_thread(run_reminders_once)
        await asyncio.to_thread(backfill_memory_once)
        await asyncio.sleep(SEASON_SYNC_INTERVAL_SECONDS)
