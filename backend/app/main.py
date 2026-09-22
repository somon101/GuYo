from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.config import get_settings
from app.routers import (
    admin_achievements,
    admin_analytics,
    admin_quests,
    admin_rating,
    admin_word_levels,
    auth,
    categories,
    dictionaries,
    exercises,
    learning,
    lessons,
    phrase_categories,
    phrases,
    quests,
    rating,
    users,
    words,
)

settings = get_settings()

Path(settings.media_root).mkdir(parents=True, exist_ok=True)

app = FastAPI(title="GuYo API", version="0.1.0")

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
app.include_router(admin_analytics.router)
app.include_router(admin_achievements.router)
app.include_router(admin_rating.router)
app.include_router(admin_word_levels.router)
app.include_router(admin_quests.router)
app.include_router(quests.router)
app.include_router(rating.router)


@app.get("/health")
def health():
    return {"status": "ok"}
