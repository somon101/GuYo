"""Turning a pasted link into the key a PromoLink is matched by.

People share the same video in many spellings -- youtu.be/ID,
youtube.com/watch?v=ID&si=..., m.youtube.com/shorts/ID, with or without
https:// or www. -- and every one of them must find the same PromoLink,
both so a real viewer's copy works and so nobody can collect the same
video twice under two spellings.

The rule: YouTube videos become "youtube:<video id>" whatever the URL
shape. Everything else becomes host + path, with the scheme, "www."/"m."
prefixes, query string, fragment and trailing slash dropped -- the query
is where share trackers live (?igsh=, ?si=, ?utm_...) and none of the
platforms GuYo posts on identify a video by it. Path case is kept:
Instagram and TikTok IDs are case-sensitive.

Short redirect links (vm.tiktok.com/..., instagr.am/...) can't be
resolved here without fetching them; the admin can add such a link as a
separate PromoLink if viewers are likely to paste it.
"""

import re
from urllib.parse import parse_qs, urlsplit

_HOST_PREFIXES = ("www.", "m.", "mobile.")
_YOUTUBE_HOSTS = {"youtube.com", "youtu.be", "music.youtube.com", "youtube-nocookie.com"}
_YOUTUBE_PATH_PREFIXES = ("shorts/", "live/", "embed/", "v/")
_YOUTUBE_ID = re.compile(r"^[A-Za-z0-9_-]{6,}$")


def looks_like_link(text: str) -> bool:
    """Whether what the user typed is a link rather than a promo code.
    Codes are letters, digits, "-" and "_" only (see normalize_code), so
    anything with a "/" or a "." in it can only be a link."""
    value = text.strip()
    return "/" in value or "." in value


def _strip_host(host: str) -> str:
    host = host.lower().rstrip(".")
    for prefix in _HOST_PREFIXES:
        if host.startswith(prefix):
            host = host[len(prefix):]
            break
    return host


def _youtube_id(host: str, path: str, query: str) -> str | None:
    if host not in _YOUTUBE_HOSTS:
        return None
    path = path.strip("/")
    if host == "youtu.be":
        candidate = path.split("/")[0]
    elif path == "watch":
        candidate = (parse_qs(query).get("v") or [""])[0]
    else:
        candidate = next(
            (path[len(prefix):].split("/")[0] for prefix in _YOUTUBE_PATH_PREFIXES if path.startswith(prefix)),
            "",
        )
    return candidate if _YOUTUBE_ID.match(candidate) else None


def normalize_link(raw: str) -> str | None:
    """The matching key for a pasted link, or None if it isn't a usable
    link at all."""
    value = raw.strip()
    if not value:
        return None
    if "://" not in value:
        value = "https://" + value
    try:
        parts = urlsplit(value)
    except ValueError:
        return None
    host = _strip_host(parts.hostname or "")
    if "." not in host:
        return None

    video_id = _youtube_id(host, parts.path, parts.query)
    if video_id is not None:
        return f"youtube:{video_id}"

    path = parts.path.rstrip("/")
    return f"{host}{path}"
