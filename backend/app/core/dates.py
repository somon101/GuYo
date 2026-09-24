"""The one place a server-side "today" is ever computed -- explicit about
WHICH timezone, never the process's own local system timezone (whatever
the host happens to be configured with, not guaranteed).

- `utc_today()`: the activity streak (app/achievements/) and season dates
  (app/rating/) -- unchanged, still UTC.
- `dushanbe_today()`: Quests' daily one-word-per-day limit
  (app/quests/service.py) -- GuYo is a Tajik-language app, so a quest's
  own "new day" boundary is explicitly Asia/Dushanbe local time, not UTC
  and never the user's own device timezone (a traveling user must see the
  same reset moment as everyone else)."""

from datetime import date, datetime, timezone
from zoneinfo import ZoneInfo

DUSHANBE_TZ = ZoneInfo("Asia/Dushanbe")


def utc_today() -> date:
    return datetime.now(timezone.utc).date()


def dushanbe_today() -> date:
    return datetime.now(timezone.utc).astimezone(DUSHANBE_TZ).date()


def utc_now() -> datetime:
    """The one server-side "right now" season scheduling compares against
    (app/rating/service.py's sync_season_states) -- always tz-aware UTC,
    so a comparison against a stored DateTime(timezone=True) can never
    silently mix naive and aware values."""
    return datetime.now(timezone.utc)


def as_utc(value: datetime) -> datetime:
    """Normalizes a datetime that crossed the API boundary. A client may
    send an offset ("2026-10-01T00:00:00+05:00") or none at all
    ("2026-10-01T00:00:00") -- a naive value is taken as UTC rather than
    as the host's own local timezone, which is never guaranteed."""
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)
