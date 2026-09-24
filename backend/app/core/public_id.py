"""The one place a GuYo account number is made.

A public_id is always exactly 9 digits (see app/models/user.py's User).
Random rather than sequential on purpose: the number is shown to people
and read aloud, and a sequential one would quietly leak how many accounts
exist and how fast they are created.
"""

import random

from sqlalchemy.orm import Session

from app.models.user import PUBLIC_ID_MAX, PUBLIC_ID_MIN, User

# Nine digits is 900 million possibilities against a few thousand
# accounts, so a collision is already vanishingly unlikely -- but the
# column is UNIQUE, so a clash would be an outright error rather than a
# silent duplicate. A handful of retries turns that into a non-event; the
# database remains the thing that actually guarantees uniqueness.
_MAX_ATTEMPTS = 10


def generate_public_id(db: Session) -> int:
    """An unused 9-digit account number.

    Raises RuntimeError only if the improbable happens repeatedly, which
    is far better than returning a number that would fail on insert with
    no explanation."""
    for _ in range(_MAX_ATTEMPTS):
        candidate = random.randint(PUBLIC_ID_MIN, PUBLIC_ID_MAX)
        exists = db.query(User.id).filter(User.public_id == candidate).first() is not None
        if not exists:
            return candidate
    raise RuntimeError("could not find a free 9-digit account number")
