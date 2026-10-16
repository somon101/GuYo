"""Mini-phrases: short ready-made constructions ("Я иду", "Я покушал") that
teach a learner to put already-known words together.

Nothing here analyses grammar. Each MiniPhrase stores its own correct text
and its parts in order (MiniPhrasePart), every part pointing at an existing
Word (and, when the phrase uses an inflected form, at that WordForm) --
never a duplicate word. A MiniPhraseTemplate says HOW a phrase is explained
and exercised, so one template serves many phrases: adding a phrase to an
existing template needs no code.
"""

from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base

# The one exercise mechanic today: the parts are shown in order in the
# explanation, then shuffled (plus distractors) for the learner to put back
# in order. A future mechanic ("Собери фразу на слух") is a new kind here.
KIND_ORDERED_PARTS = "ordered_parts"
TEMPLATE_KINDS = (KIND_ORDERED_PARTS,)

# The word roles an explanation can refer to ({pronoun}, {verb}, ...). Set
# once per Word (Word.role), optionally overridden per part.
WORD_ROLES = ("pronoun", "verb", "noun", "adjective", "adverb", "preposition", "number", "other")


class MiniPhraseTemplate(Base):
    """How a group of mini-phrases is explained and exercised. The
    explanation is a text with placeholders (see app/mini_phrases/render.py)
    written once per interface language, so one template explains every
    phrase that shares its structure."""

    __tablename__ = "mini_phrase_templates"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(128), nullable=False)
    kind: Mapped[str] = mapped_column(String(32), nullable=False, default=KIND_ORDERED_PARTS, server_default=KIND_ORDERED_PARTS)
    explanation_ru: Mapped[str | None] = mapped_column(Text, nullable=True)
    explanation_tg: Mapped[str | None] = mapped_column(Text, nullable=True)
    explanation_uz: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Extra wrong tiles in "Собери фразу", drawn from the learner's learned
    # words by priority (app/priority/distractors.py).
    distractor_count: Mapped[int] = mapped_column(Integer, nullable=False, default=2, server_default="2")
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class MiniPhrase(Base):
    __tablename__ = "mini_phrases"

    id: Mapped[int] = mapped_column(primary_key=True)
    dictionary_id: Mapped[int] = mapped_column(
        ForeignKey("dictionaries.id", ondelete="CASCADE"), nullable=False, index=True
    )
    template_id: Mapped[int | None] = mapped_column(
        ForeignKey("mini_phrase_templates.id", ondelete="SET NULL"), nullable=True, index=True
    )
    # The correct answer, exactly as it should read in the studied language.
    text: Mapped[str] = mapped_column(String(500), nullable=False)
    # Язык фразы. Мини-фраза собрана из языковых записей ОДНОГО языка и
    # показывается только тем, кто этот язык изучает (см.
    # docs/multilingual-migration.md). До многоязычной перестройки язык
    # подразумевался языком словаря, поэтому поле nullable: старые строки
    # заполняет перенос данных (app/multilingual_backfill.py).
    language: Mapped[str | None] = mapped_column(String(8), nullable=True, index=True)
    translation_tg: Mapped[str] = mapped_column(String(500), nullable=False)
    translation_uz: Mapped[str | None] = mapped_column(String(500), nullable=True)
    translation_en: Mapped[str | None] = mapped_column(String(500), nullable=True)
    # For a future "Собери фразу на слух"; optional today.
    audio_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    template: Mapped["MiniPhraseTemplate | None"] = relationship()
    parts: Mapped[list["MiniPhrasePart"]] = relationship(
        back_populates="mini_phrase", cascade="all, delete-orphan", order_by="MiniPhrasePart.position"
    )


class MiniPhrasePart(Base):
    """One part of a mini-phrase, in order. `text` is how it reads in the
    phrase ("покушал"); `word_id` is the dictionary word it belongs to
    ("кушать"), `word_form_id` the exact form when it isn't the base word.
    `role` overrides the word's own role for this phrase only."""

    __tablename__ = "mini_phrase_parts"
    __table_args__ = (UniqueConstraint("mini_phrase_id", "position", name="uq_mini_phrase_part_position"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    mini_phrase_id: Mapped[int] = mapped_column(
        ForeignKey("mini_phrases.id", ondelete="CASCADE"), nullable=False, index=True
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    text: Mapped[str] = mapped_column(String(255), nullable=False)
    word_id: Mapped[int] = mapped_column(ForeignKey("words.id", ondelete="CASCADE"), nullable=False, index=True)
    word_form_id: Mapped[int | None] = mapped_column(
        ForeignKey("word_forms.id", ondelete="SET NULL"), nullable=True
    )
    role: Mapped[str | None] = mapped_column(String(32), nullable=True)

    mini_phrase: Mapped["MiniPhrase"] = relationship(back_populates="parts")
    word: Mapped["Word"] = relationship()
    word_form: Mapped["WordForm | None"] = relationship()


class LessonMiniPhrase(Base):
    """A mini-phrase frozen into a lesson when the lesson was created, like
    LessonWord: shown after the word exercises on every pass until the
    lesson is completed."""

    __tablename__ = "lesson_mini_phrases"
    __table_args__ = (UniqueConstraint("lesson_id", "mini_phrase_id", name="uq_lesson_mini_phrase"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    lesson_id: Mapped[int] = mapped_column(ForeignKey("lessons.id", ondelete="CASCADE"), nullable=False, index=True)
    mini_phrase_id: Mapped[int] = mapped_column(
        ForeignKey("mini_phrases.id", ondelete="CASCADE"), nullable=False, index=True
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")

    mini_phrase: Mapped["MiniPhrase"] = relationship()


class UserMiniPhraseDone(Base):
    """The user has gone through this mini-phrase in a lesson: it is "open"
    (listed in Практика) and never attached to another lesson again."""

    __tablename__ = "user_mini_phrase_done"
    __table_args__ = (UniqueConstraint("user_id", "mini_phrase_id", name="uq_user_mini_phrase_done"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    mini_phrase_id: Mapped[int] = mapped_column(
        ForeignKey("mini_phrases.id", ondelete="CASCADE"), nullable=False, index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class UserMiniPhrasePoints(Base):
    """One rating grant for assembling a mini-phrase right -- at most once
    per (user, mini-phrase), wherever it first happened. `points_awarded` is
    a snapshot of the setting at that moment; read by "очков сегодня"."""

    __tablename__ = "user_mini_phrase_points"
    __table_args__ = (UniqueConstraint("user_id", "mini_phrase_id", name="uq_user_mini_phrase_points"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    mini_phrase_id: Mapped[int] = mapped_column(
        ForeignKey("mini_phrases.id", ondelete="CASCADE"), nullable=False, index=True
    )
    points_awarded: Mapped[int] = mapped_column(Integer, nullable=False)
    awarded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


class MiniPhraseSettings(Base):
    """Single-row table (always id=1), created lazily with defaults -- same
    idiom as RatingSettings/LearningSettings."""

    __tablename__ = "mini_phrase_settings"

    id: Mapped[int] = mapped_column(primary_key=True)
    points_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    points_per_correct: Mapped[int] = mapped_column(Integer, nullable=False, default=5, server_default="5")
    max_per_lesson: Mapped[int] = mapped_column(Integer, nullable=False, default=3, server_default="3")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
