"""«Проверка текста»: the AI grammar/style checker's own storage.

Three pieces, each with one job:

- [TextCheckSettings] -- the single admin row: whether the feature is on, how
  long a message may be, and how many checks a free and a Premium user get
  per day. NULL means "no limit at all", the same idiom PremiumSettings uses
  for lessons.

- [TextCheckRun] -- one row per check a user asked for. This is the journal
  the daily limit is counted from (the same way lessons are counted: rows
  since the start of the Dushanbe day), and it is what Admin Web's numbers
  are built from. A check served from the cache, or one DeepSeek failed to
  answer, is recorded here too -- but neither counts against anybody's limit,
  because neither cost anything (see app/text_check/service.py).

- [TextCheckCache] -- answers already produced for one exact text under one
  exact set of settings. Exact means exact: same message, same own gender,
  same addressee, same formality, same punctuation choice, same explanation
  language.

  A merely SIMILAR text is deliberately never reused. For a checker the
  difference between two texts IS the answer -- one wrong letter is exactly
  what the user came to find out -- so a "90% match" would cheerfully answer
  "всё правильно" to a typo and teach the learner something false. Only case
  and the spaces around the text are normalized, because the prompt is told
  never to judge case and edge spaces cannot be a mistake.

  The fingerprint carries the prompt's own hash and the model name as well,
  so editing the prompt (or switching models) retires every old entry by
  itself, with nothing to clean up by hand.
"""

from datetime import datetime

from sqlalchemy import JSON, Boolean, CheckConstraint, DateTime, ForeignKey, Index, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

# A checked message can never be longer than this, whatever the admin sets
# the current limit to -- the cache and journal columns are sized for it.
MAX_STORED_TEXT = 2000


class TextCheckSettings(Base):
    """Single-row table (always id=1), created lazily with its defaults on
    first read -- the same idiom as PremiumSettings, LearningSettings and
    every other admin-configured row in this project."""

    __tablename__ = "text_check_settings"
    __table_args__ = (
        CheckConstraint("max_chars >= 1", name="ck_text_check_max_chars"),
        CheckConstraint("free_daily_limit IS NULL OR free_daily_limit >= 0", name="ck_text_check_free_daily"),
        CheckConstraint("premium_daily_limit IS NULL OR premium_daily_limit >= 0", name="ck_text_check_premium_daily"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)

    # The whole feature's switch: off means every app call is answered with a
    # plain "not available" instead of being sent to DeepSeek.
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")

    # The longest message the admin allows. The backend enforces it (the
    # request schema is built from it) and the app shows it as the field's own
    # limit, so changing it here is felt in the app without a new build.
    max_chars: Mapped[int] = mapped_column(Integer, nullable=False, default=500, server_default="500")

    # Checks per Dushanbe day. NULL = unlimited (which is what Premium gets by
    # default); 0 = nobody may check at all.
    free_daily_limit: Mapped[int | None] = mapped_column(Integer, nullable=True, default=5, server_default="5")
    premium_daily_limit: Mapped[int | None] = mapped_column(Integer, nullable=True, default=None)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class TextCheckRun(Base):
    """One check a user asked for -- the limit's counter, the admin's statistics,
    AND the check itself: the text as written, the prompt the model was given and
    the whole answer it gave.

    The text/prompt/answer are kept HERE rather than only in TextCheckCache
    because the cache is keyed by the normalized text: it can say "this text was
    checked", but never "this user checked it, on this day, and this is what came
    back". Admin Web lists these as cards -- who wrote it, what was asked, what
    was answered -- which is exactly what the cache cannot show."""

    __tablename__ = "text_check_runs"
    __table_args__ = (
        # The quota query is "this user's rows since the day started", so the
        # index leads with the user and then walks the date.
        Index("ix_text_check_runs_user_created", "user_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True)

    # How long the message was -- the one number the admin needs to see how
    # much text people actually check.
    chars: Mapped[int] = mapped_column(Integer, nullable=False)

    # Answered from the cache: it cost nothing, so it is not counted against
    # the daily limit.
    cached: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")

    # False when DeepSeek could not answer at all. Kept for the statistics;
    # like a cache hit, it never counts against the limit.
    succeeded: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")

    # --- the check itself ---------------------------------------------------
    # NULL on rows written before these columns existed: the older checks only
    # have a length, and Admin Web says so instead of showing an empty card.
    text: Mapped[str | None] = mapped_column(Text, nullable=True)
    # The exact prompt sent to the model, and the exact answer it returned.
    prompt: Mapped[str | None] = mapped_column(Text, nullable=True)
    answer: Mapped[str | None] = mapped_column(Text, nullable=True)
    # The settings this check ran with (user_gender, addressee_gender, formality,
    # check_punctuation, explanation_language): the answer only means anything
    # next to the settings that produced it.
    params: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    model: Mapped[str | None] = mapped_column(String(64), nullable=True)
    # The account's own name at the time, so a card stays readable (and a check
    # stays attributable) even if the account is later removed.
    user_login: Mapped[str] = mapped_column(String(64), nullable=False, default="", server_default="")


class TextCheckCache(Base):
    """One already-checked text under one exact set of settings."""

    __tablename__ = "text_check_cache"

    id: Mapped[int] = mapped_column(primary_key=True)

    # sha256 over: the prompt's own hash, the model name, every setting that
    # can change the answer, and the normalized text. Unique, so the same
    # question can only ever have one row.
    fingerprint: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)

    # The message as it was normalized for the key (trimmed, lower-cased).
    # Stored so Admin Web can show what people actually check, and so a bad
    # answer can be found and deleted by hand.
    text: Mapped[str] = mapped_column(String(MAX_STORED_TEXT), nullable=False)

    # The settings this answer belongs to, as they were sent: user_gender,
    # addressee_gender, formality, check_punctuation, explanation_language.
    params: Mapped[dict] = mapped_column(JSON, nullable=False)

    # The answer exactly as the API returns it.
    result: Mapped[dict] = mapped_column(JSON, nullable=False)

    # How many times this entry was served -- the cache's own value, and the
    # "самые частые тексты" list in Admin Web.
    hits: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
