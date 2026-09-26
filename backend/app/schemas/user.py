from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

# The fixed option sets self-registration's own steps offer -- a plain
# Literal (not an admin-configurable table like WordLevel/Quest elsewhere
# in this codebase) because the spec treats these as a closed, known set
# a future change edits here in code, not something an admin tunes at
# runtime. Values are what the client sends; the Russian labels are the
# client's own concern (see mobile/lib/screens/register_screen.dart).
AgeGroup = Literal["12-17", "18-24", "25+"]
LearningGoal = Literal["study", "work", "communication", "travel", "relocation", "personal", "other"]
ReferralSource = Literal["social", "youtube", "telegram", "search", "friends", "ads", "other"]


def normalize_email(value: str) -> str:
    """Trims and lower-cases an address, and rejects the obviously wrong.

    A deliberate sanity check, not RFC validation: the only way to really
    know an address works is to send to it, and pulling in a validation
    library to be stricter about a field nothing sends mail to yet would
    buy nothing. It does catch the mistakes people actually make -- a
    missing @, a stray space, a domain with no dot.

    Lower-cased so the unique constraint means what a person expects:
    "Somon@Mail.ru" and "somon@mail.ru" are one address, not two."""
    email = value.strip().lower()
    local, separator, domain = email.partition("@")
    if not separator or not local or not domain or "." not in domain:
        raise ValueError("Некорректный адрес электронной почты")
    if any(ch.isspace() for ch in email):
        raise ValueError("Адрес электронной почты не должен содержать пробелов")
    return email


class UserCreate(BaseModel):
    """Everything a NEW account must have. Deliberately stricter than the
    database, which keeps the personal fields nullable so accounts created
    before they existed keep working -- those older accounts simply never
    go through this schema again."""

    login: str = Field(min_length=3, max_length=64)
    password: str = Field(min_length=4, max_length=128)
    first_name: str = Field(min_length=1, max_length=100)
    last_name: str = Field(min_length=1, max_length=100)
    email: str = Field(min_length=3, max_length=255)

    @field_validator("email")
    @classmethod
    def _check_email(cls, value: str) -> str:
        return normalize_email(value)


class RegisterIn(BaseModel):
    """Self-registration, from the app's own multi-step sign-up (see
    mobile/lib/screens/register_screen.dart) -- everything UserCreate
    needs, plus the confirmation field this endpoint alone checks, plus
    the three profile choices and the chosen learning language. Not a
    parallel account-creation path: app/routers/auth.py's register_user
    builds the exact same User row admin_router's create_user does."""

    login: str = Field(min_length=3, max_length=64)
    password: str = Field(min_length=4, max_length=128)
    password_confirm: str = Field(min_length=4, max_length=128)
    first_name: str = Field(min_length=1, max_length=100)
    last_name: str = Field(min_length=1, max_length=100)
    email: str = Field(min_length=3, max_length=255)
    # A Dictionary.language code (e.g. "en") from GET /dictionaries/public
    # -- never validated against that list here, same trust boundary as
    # every other dictionary_id/language a logged-in request already
    # sends; worst case an unrecognized code just never matches a
    # dictionary later, exactly like it would for an existing account.
    learning_language: str = Field(min_length=1, max_length=16)
    age_group: AgeGroup
    learning_goal: LearningGoal
    referral_source: ReferralSource

    @field_validator("email")
    @classmethod
    def _check_email(cls, value: str) -> str:
        return normalize_email(value)

    @model_validator(mode="after")
    def _check_passwords_match(self) -> "RegisterIn":
        if self.password != self.password_confirm:
            raise ValueError("Пароли не совпадают")
        return self


class UserUpdateIn(BaseModel):
    """What a user may change about themselves. Every field optional --
    only what is sent is changed -- and the photo is NOT here: it is a
    file, and already has its own upload/delete endpoints.

    Notably absent too: the password and the account number. The number is
    permanent by definition, and changing a password is a different
    operation with its own rules."""

    login: str | None = Field(default=None, min_length=3, max_length=64)
    first_name: str | None = Field(default=None, min_length=1, max_length=100)
    last_name: str | None = Field(default=None, min_length=1, max_length=100)
    email: str | None = Field(default=None, min_length=3, max_length=255)

    @field_validator("email")
    @classmethod
    def _check_email(cls, value: str | None) -> str | None:
        return None if value is None else normalize_email(value)


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    # The 9-digit number people actually see -- `id` above stays internal.
    public_id: int
    login: str
    first_name: str | None
    last_name: str | None
    email: str | None
    created_at: datetime


class UserProfileOut(BaseModel):
    """The Profile screen's own view of the current user: their permanent
    `id` (never `login`, which is only credentials/display text), their
    avatar -- a real uploaded photo's URL, or null when the client should
    render its own generated default avatar instead -- and their current
    activity streak. Both avatar_key and the streak (UserActivityDay) live
    in Postgres, never on the device, so a login from a different phone
    sees the exact same values.

    `current_streak_days`, `lessons_completed` and `words_learned` all
    reuse app/achievements/conditions.py's own counters -- the SAME numbers
    the "Активность"/"Уроки"/"Слова" achievement condition_types are
    evaluated against -- never a second definition of any of them, and
    shown here even when no admin has configured a matching achievement at
    all."""

    id: int
    # The 9-digit account number shown in the profile. `id` stays the
    # internal key -- never displayed, never changes.
    public_id: int
    login: str
    # Null on accounts created before these existed; the UI shows an empty
    # field rather than inventing anything.
    first_name: str | None
    last_name: str | None
    email: str | None
    avatar_url: str | None
    current_streak_days: int
    lessons_completed: int
    words_learned: int
    # Null when the user doesn't have GuYo Premium right now -- see
    # app/premium/service.py's premium_until, the one definition of it.
    premium_until: datetime | None = None
    # Collected once at self-registration; null on any account made
    # another way. Not shown/edited anywhere in the app yet -- kept here
    # so that becomes possible later without another migration.
    learning_language: str | None = None
    age_group: str | None = None
    learning_goal: str | None = None
    referral_source: str | None = None
