"""Test setup: a throw-away Postgres database built by the real migrations,
emptied of people and content between tests.

Run from backend/:  pytest
Needs a Postgres the TEST_DATABASE_URL (default: postgresql+psycopg://guyo:guyo@localhost:5432/guyo_test)
can reach, with permission to drop and create that database."""

import os
import itertools
from datetime import timedelta
from pathlib import Path

import psycopg
import pytest

TEST_URL = os.environ.get("TEST_DATABASE_URL", "postgresql+psycopg://guyo:guyo@localhost:5432/guyo_test")
# Must be set before the app is imported: settings are read at import time.
os.environ["DATABASE_URL"] = TEST_URL
os.environ.setdefault("JWT_SECRET", "test-secret-not-for-production")

BACKEND = Path(__file__).resolve().parent.parent


def _admin_conninfo() -> tuple[str, str]:
    """(conninfo of the server's 'postgres' database, name of the test database)."""
    rest = TEST_URL.split("://", 1)[1]
    creds, location = rest.split("@", 1)
    host_port, name = location.rsplit("/", 1)
    user, _, password = creds.partition(":")
    host, _, port = host_port.partition(":")
    return f"host={host} port={port or 5432} user={user} password={password} dbname=postgres", name


@pytest.fixture(scope="session", autouse=True)
def _database():
    conninfo, name = _admin_conninfo()
    with psycopg.connect(conninfo, autocommit=True) as conn:
        conn.execute(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)')
        conn.execute(f'CREATE DATABASE "{name}"')
    from alembic import command
    from alembic.config import Config

    cfg = Config(str(BACKEND / "alembic.ini"))
    cfg.set_main_option("script_location", str(BACKEND / "alembic"))
    command.upgrade(cfg, "head")
    yield


# What a test creates; everything that hangs off these goes with them.
_WIPE = "duels, users, admins, dictionaries, seasons, pass_templates, pass_settings, reminder_settings, teams, categories"


@pytest.fixture(autouse=True)
def _clean(_database):
    yield
    from app.database import engine

    with engine.begin() as conn:
        conn.exec_driver_sql(f"TRUNCATE {_WIPE} RESTART IDENTITY CASCADE")


@pytest.fixture
def db():
    from app.database import SessionLocal

    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture
def client():
    from fastapi.testclient import TestClient

    from app.main import app

    return TestClient(app)  # no lifespan: the season scheduler stays off


_public_ids = itertools.count(900_000_001)


@pytest.fixture
def make_user(db):
    from app.models.user import User

    def make(login: str | None = None, **fields) -> User:
        pid = next(_public_ids)
        user = User(login=login or f"user{pid}", password_hash="x", public_id=pid, **fields)
        db.add(user)
        db.commit()
        return user

    return make


@pytest.fixture
def auth():
    from app.core.security import create_access_token

    def headers(user, role: str = "user") -> dict:
        return {"Authorization": f"Bearer {create_access_token(subject=user.id, role=role)}", "X-App-Build": "99999"}

    return headers


@pytest.fixture
def admin_headers(db, auth):
    from app.models.admin import Admin

    admin = Admin(login="testadmin", password_hash="x")
    db.add(admin)
    db.commit()
    return auth(admin, role="admin")


@pytest.fixture
def make_dictionary(db):
    """A published dictionary with `n` words, each with its own translation."""
    from app.models.dictionary import Dictionary
    from app.models.word import Word, WordTranslation

    def make(n: int = 16) -> Dictionary:
        d = Dictionary(name="Test", language="en", is_published=True)
        db.add(d)
        db.flush()
        for i in range(n):
            w = Word(dictionary_id=d.id, word=f"word{i:02d}", importance=3)
            db.add(w)
            db.flush()
            db.add(WordTranslation(word_id=w.id, language="tg", text=f"tarjuma{i:02d}"))
        db.commit()
        return d

    return make


@pytest.fixture
def active_season(db):
    """The season that is running now (the one XP goes to)."""
    from app.core.dates import utc_now
    from app.models.rating import SEASON_ACTIVE, Season

    now = utc_now()
    season = Season(
        name="Тестовый сезон", starts_at=now - timedelta(days=1), ends_at=now + timedelta(days=20), status=SEASON_ACTIVE
    )
    db.add(season)
    db.commit()
    return season
