"""The one place a server-side "today" is ever computed -- explicit about
WHICH timezone, never the process's own local system timezone (whatever
the host happens to be configured with, not guaranteed).

- `utc_today()`: the activity streak (app/achievements/) and season dates
  (app/rating/) -- unchanged, still UTC.
- `dushanbe_today()`: Quests' daily one-word-per-day limit
  (app/quests/service.py), the greeting slogan's own day
  (app/slogans/service.py), and Premium's daily/weekly lesson limits
  (app/premium/service.py) -- GuYo is a Tajik-language app, so a "new day"
  boundary is explicitly Asia/Dushanbe local time, not UTC and never the
  user's own device timezone (a traveling user must see the same reset
  moment as everyone else).

  Note the one deliberate exception, which is NOT a server concern at all:
  the greeting's sun/moon icon is chosen from the DEVICE's own clock in
  the Flutter app (mobile/lib/theme/time_of_day.dart). Nothing here is
  involved in it -- a user in Berlin must see their own evening even
  though their slogan turns over on Dushanbe's midnight."""

from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

DUSHANBE_TZ = ZoneInfo("Asia/Dushanbe")


def utc_today() -> date:
    return datetime.now(timezone.utc).date()


def dushanbe_today() -> date:
    return datetime.now(timezone.utc).astimezone(DUSHANBE_TZ).date()


def dushanbe_day_start(today: date | None = None) -> datetime:
    """The UTC instant the current Asia/Dushanbe day began -- what "today"
    means for Premium's daily lesson limit (app/premium/service.py), the
    same boundary as dushanbe_today()."""
    day = today or dushanbe_today()
    return datetime.combine(day, time.min, tzinfo=DUSHANBE_TZ).astimezone(timezone.utc)


def dushanbe_week_start(today: date | None = None) -> datetime:
    """The UTC instant the current Asia/Dushanbe calendar week began,
    Monday 00:00 -- what "this week" means for Premium's weekly lesson
    limit. A calendar week, not a rolling 7 days, so a user can be told
    plainly "обновится в понедельник"."""
    day = today or dushanbe_today()
    return dushanbe_day_start(day - timedelta(days=day.weekday()))


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
