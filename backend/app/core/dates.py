"""The one place "today" is ever computed server-side -- always UTC,
never the process's local system timezone (which is whatever the host
happens to be configured with, not guaranteed). Every "day" boundary
that matters for a user (activity streak, a quest's daily one-word
limit, a season's own dates) reads through this, so they all agree on
the same day at the same instant no matter where the process runs."""

from datetime import date, datetime, timezone


def utc_today() -> date:
    return datetime.now(timezone.utc).date()
