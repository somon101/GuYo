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
