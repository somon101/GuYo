"""Application configuration, loaded from environment variables / .env."""
from functools import lru_cache

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


def _normalize_database_url(url: str) -> str:
    """Managed Postgres providers (Railway included) hand out a plain
    postgres://... / postgresql://... URL. SQLAlchemy needs the psycopg3
    driver spelled out, so rewrite the scheme rather than requiring every
    deployment target to know about that detail."""
    if url.startswith("postgres://"):
        return "postgresql+psycopg://" + url[len("postgres://"):]
    if url.startswith("postgresql://"):
        return "postgresql+psycopg://" + url[len("postgresql://"):]
    return url


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    database_url: str = "postgresql+psycopg://guyo:guyo@localhost:5432/guyo"

    @field_validator("database_url")
    @classmethod
    def _fix_database_url_scheme(cls, v: str) -> str:
        return _normalize_database_url(v)

    jwt_secret: str = "insecure-dev-secret-change-me"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 1440

    allowed_origins: str = "http://localhost:5173,http://127.0.0.1:5173"
    # The oldest app build (the "+N" of the app's version) still allowed to
    # answer exercises. 0 = no check. Raise it once a release everyone
    # should have is out: older apps are then told to update.
    min_app_build: int = 0
    # Server error reporting (Sentry). Empty = off.
    sentry_dsn: str = ""

    media_root: str = "./storage"
    media_url_prefix: str = "/media"

    seed_admin_login: str = "admin"
    seed_admin_password: str = "123456"

    # The Firebase service-account key file's full JSON text. Empty means
    # push is off: notifications still land in the in-app inbox.
    firebase_service_account_json: str = ""

    # Google Sign-In: the OAuth client IDs (comma-separated) an ID token may
    # be issued for -- the Web client ID the app requests tokens with. Not a
    # secret. Empty means "Войти через Google" is off.
    google_client_ids: str = "656681360823-dihp65s7tiq23v3gcbtpcfdhnfs95s77.apps.googleusercontent.com"

    @property
    def cors_origins(self) -> list[str]:
        return [origin.strip() for origin in self.allowed_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
