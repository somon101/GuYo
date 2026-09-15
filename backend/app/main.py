from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.config import get_settings
from app.routers import auth, categories, dictionaries, users, words

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


@app.get("/health")
def health():
    return {"status": "ok"}
