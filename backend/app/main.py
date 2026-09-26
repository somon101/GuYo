import asyncio
import contextlib
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.config import get_settings
from app.rating.scheduler import run_season_scheduler
from app.routers import (
    admin_achievements,
    admin_analytics,
    admin_priority,
    admin_quests,
    admin_rating,
    admin_slogans,
    admin_word_levels,
    auth,
    categories,
    dictionaries,
    exercises,
    learning,
    lessons,
    notifications,
    phrase_categories,
    phrases,
    practice,
    premium,
    promo,
    quests,
    rating,
    slogans,
    users,
    word_levels,
    words,
)

settings = get_settings()

Path(settings.media_root).mkdir(parents=True, exist_ok=True)

@asynccontextmanager
async def lifespan(_app: FastAPI):
    """Starts the season scheduler for the lifetime of the process. Its
    very first sweep is the "catch up on everything that happened while we
    were down" pass -- see app/rating/scheduler.py."""
    task = asyncio.create_task(run_season_scheduler())
    try:
        yield
    finally:
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await task


app = FastAPI(title="GuYo API", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount(
    settings.media_url_prefix,
    StaticFiles(directory=settings.media_root),
    name="media",
)

app.include_router(auth.router)
app.include_router(users.router)
app.include_router(dictionaries.router)
app.include_router(words.router)
app.include_router(categories.router)
app.include_router(phrases.router)
app.include_router(phrase_categories.router)
app.include_router(learning.router)
app.include_router(exercises.router)
app.include_router(lessons.router)
app.include_router(practice.router)
app.include_router(admin_analytics.router)
app.include_router(admin_priority.router)
app.include_router(admin_achievements.router)
app.include_router(admin_rating.router)
app.include_router(admin_word_levels.router)
app.include_router(admin_quests.router)
app.include_router(admin_slogans.router)
app.include_router(notifications.admin_router)
app.include_router(quests.router)
app.include_router(rating.router)
app.include_router(word_levels.router)
app.include_router(slogans.router)
app.include_router(notifications.router)
app.include_router(premium.router)
app.include_router(premium.admin_router)
app.include_router(promo.router)
app.include_router(promo.admin_router)


@app.get("/health")
def health():
    return {"status": "ok"}
