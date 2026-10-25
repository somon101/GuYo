from fastapi.exception_handlers import http_exception_handler
from starlette.exceptions import HTTPException as StarletteHTTPException
import asyncio
import contextlib
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.config import get_settings
from app.core.content_language import begin_request
from app.rating.scheduler import run_season_scheduler
from app.routers import (
    admin_achievements,
    admin_ai,
    admin_languages,
    admin_mini_phrases,
    mini_phrases,
    admin_memory,
    admin_translation,
    admin_backup,
    events,
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
    lesson_check,
    season_pass,
    daily_goal,
    my_progress,
    duels,
    chests,
    teams,
    admin_season_pass,
    cosmetics as cosmetics_routes,
    notifications,
    phrase_categories,
    phrases,
    practice,
    premium,
    promo,
    client_errors,
    quests,
    rating,
    slogans,
    text_check,
    users,
    word_levels,
    words,
)
from app.routers import api_keys
from app.routers import languages
from app.routers import status as status_router
from app.economy import routes as economy_routes

settings = get_settings()

if settings.sentry_dsn:
    # Unhandled server errors go to Sentry with their request context.
    import sentry_sdk

    sentry_sdk.init(dsn=settings.sentry_dsn, traces_sample_rate=0.0, send_default_pii=False)

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


@app.exception_handler(StarletteHTTPException)
async def _http_error(request, exc: StarletteHTTPException):
    """Shows people's errors in the interface language the app sent."""
    from app.core.messages import localize

    detail = localize(exc.detail, request.headers.get("x-ui-language"))
    return await http_exception_handler(request, StarletteHTTPException(exc.status_code, detail, exc.headers))


@app.middleware("http")
async def content_language_scope(request, call_next):
    # Fresh per-request language holder (app/core/content_language.py).
    begin_request()
    return await call_next(request)


app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.middleware("http")
async def public_api_cors(request, call_next):
    # The external API (/api/v1) is opened to any origin: access is decided by
    # the API key, not by where the call comes from. Added after CORSMiddleware,
    # so it runs first and answers the browser's preflight itself.
    if not request.url.path.startswith("/api/v1"):
        return await call_next(request)
    from fastapi.responses import Response

    headers = {
        "Access-Control-Allow-Origin": request.headers.get("origin") or "*",
        "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "X-API-Key, Authorization, Content-Type",
        "Access-Control-Max-Age": "86400",
        "Vary": "Origin",
    }
    if request.method == "OPTIONS":
        return Response(status_code=204, headers=headers)
    response = await call_next(request)
    for k, v in headers.items():
        response.headers[k] = v
    return response


app.mount(
    settings.media_url_prefix,
    StaticFiles(directory=settings.media_root),
    name="media",
)

app.include_router(api_keys.admin_router)
app.include_router(api_keys.api_router)
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
app.include_router(lesson_check.router)
app.include_router(season_pass.router)
app.include_router(daily_goal.router)
app.include_router(my_progress.router)
app.include_router(duels.router)
app.include_router(chests.router)
app.include_router(chests.admin_router)
app.include_router(chests.boosters_router)
app.include_router(economy_routes.shop_router)
app.include_router(economy_routes.admin_router)
app.include_router(teams.router)
app.include_router(admin_season_pass.router)
app.include_router(cosmetics_routes.router)
app.include_router(cosmetics_routes.admin_router)
app.include_router(practice.router)
app.include_router(admin_analytics.router)
app.include_router(admin_priority.router)
app.include_router(admin_memory.router)
app.include_router(admin_translation.router)
app.include_router(admin_backup.router)
app.include_router(events.router)
app.include_router(admin_achievements.router)
app.include_router(admin_mini_phrases.router)
app.include_router(admin_languages.router)
app.include_router(languages.router)
app.include_router(mini_phrases.router)
app.include_router(admin_rating.router)
app.include_router(admin_word_levels.router)
app.include_router(admin_quests.router)
app.include_router(admin_slogans.router)
app.include_router(status_router.admin_router)
app.include_router(notifications.admin_router)
app.include_router(quests.router)
app.include_router(rating.router)
app.include_router(word_levels.router)
app.include_router(slogans.router)
app.include_router(status_router.router)
app.include_router(notifications.router)
app.include_router(premium.router)
app.include_router(premium.admin_router)
app.include_router(promo.router)
app.include_router(promo.admin_router)
app.include_router(client_errors.router)
app.include_router(text_check.router)
app.include_router(admin_ai.router)


@app.get("/health")
def health():
    return {"status": "ok"}
