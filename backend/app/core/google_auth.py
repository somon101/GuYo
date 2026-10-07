"""Checks a Google Sign-In ID token (sent by the app after the user picks a
Google account) and returns who it belongs to.

Uses Google's own tokeninfo endpoint, so no extra library: it verifies the
signature and expiry; we check it was issued for GuYo (`aud` is one of our
OAuth client IDs) and that Google has verified the email.
"""

import requests

from app.config import get_settings

TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"
ISSUERS = ("accounts.google.com", "https://accounts.google.com")


class GoogleTokenError(Exception):
    pass


def client_ids() -> list[str]:
    return [c.strip() for c in get_settings().google_client_ids.split(",") if c.strip()]


def verify_google_id_token(id_token: str) -> dict:
    """Returns {sub, email, first_name, last_name} or raises GoogleTokenError."""
    allowed = client_ids()
    if not allowed:
        raise GoogleTokenError("Вход через Google ещё не настроен")
    try:
        response = requests.get(TOKENINFO_URL, params={"id_token": id_token}, timeout=10)
    except requests.RequestException as e:
        raise GoogleTokenError("Не удалось связаться с Google") from e
    if response.status_code != 200:
        raise GoogleTokenError("Google не подтвердил вход")
    info = response.json()
    if info.get("aud") not in allowed or info.get("iss") not in ISSUERS:
        raise GoogleTokenError("Токен выдан не для GuYo")
    if str(info.get("email_verified")).lower() != "true" or not info.get("email"):
        raise GoogleTokenError("Почта в Google не подтверждена")
    return {
        "sub": info["sub"],
        "email": info["email"].strip().lower(),
        "first_name": (info.get("given_name") or "").strip(),
        "last_name": (info.get("family_name") or "").strip(),
    }
