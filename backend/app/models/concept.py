"""Понятие и языковые записи — многоязычная основа.

Смысл («человек») отделён от того, как он выглядит в каждом языке:

* **Понятие** (`concepts`) хранит ОБЩУЮ классификацию: категорию, важность,
  роль, картинку, темы. Одна на все языки — не дублируется.
* **Языковая запись** (`word_entries`) хранит то, что у каждого языка своё:
  написание, транскрипцию, аудио. Плюс свои формы (`word_entry_forms`).
* **Перевода как отдельной сущности больше нет**: перевод — это языковая
  запись того же понятия на другом языке. Аудио перевода, которое уже
  хранилось в `word_translations.audio_key`, становится `audio_key` записи.

Таблицы созданы РЯДОМ со старой структурой (`app/models/word.py`): приложение
пока работает на ней, перенос данных — отдельный этап, чтобы бой не
останавливался. Порядок и проверки: docs/multilingual-migration.md.

Фразы устроены так же (`phrase_concepts` + `phrase_entries`), чтобы у слов,
фраз и мини-фраз была одна модель.
"""

from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Concept(Base):
    """Смысл, общий для всех языков. Всё, что не зависит от языка, живёт здесь."""

    __tablename__ = "concepts"

    id: Mapped[int] = mapped_column(primary_key=True)
    # Словарь остаётся набором понятий (темой/курсом); направление изучения --
    # это пара языков у человека, а не свойство понятия.
    dictionary_id: Mapped[int] = mapped_column(
        ForeignKey("dictionaries.id", ondelete="CASCADE"), nullable=False, index=True
    )
    category_id: Mapped[int | None] = mapped_column(
        ForeignKey("categories.id", ondelete="SET NULL"), nullable=True, index=True
    )
    # 1-5, 5 = самое нужное новичку (то же значение, что у Word.importance).
    importance: Mapped[int] = mapped_column(Integer, nullable=False, default=3, server_default="3")
    # Роль в предложении ("pronoun", "verb", ...): по ней объясняются части
    # мини-фраз на ЛЮБОМ языке, поэтому роль живёт у понятия, а не у записи.
    role: Mapped[str | None] = mapped_column(String(32), nullable=True)
    image_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    entries: Mapped[list["WordEntry"]] = relationship(
        back_populates="concept", cascade="all, delete-orphan", order_by="WordEntry.id"
    )
    topics: Mapped[list["ConceptTopic"]] = relationship(
        cascade="all, delete-orphan", order_by="ConceptTopic.id"
    )


class ConceptTopic(Base):
    """Тема понятия (бывшие `word_topics`): общая для всех языков."""

    __tablename__ = "concept_topics"

    id: Mapped[int] = mapped_column(primary_key=True)
    concept_id: Mapped[int] = mapped_column(
        ForeignKey("concepts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    topic: Mapped[str] = mapped_column(String(32), nullable=False)


class WordEntry(Base):
    """Как понятие выглядит в одном языке: написание, транскрипция, аудио.

    `id` при переносе СОХРАНЯЕТ id нынешнего `Word` для языка словаря — тогда
    прогресс, память, уровни, история ответов и рейтинг продолжают работать без
    изменений (они ссылаются на тот же id). Остальные языки получают новые id.
    """

    __tablename__ = "word_entries"
    __table_args__ = (UniqueConstraint("concept_id", "language", name="uq_word_entry_concept_language"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    concept_id: Mapped[int] = mapped_column(
        ForeignKey("concepts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    language: Mapped[str] = mapped_column(String(8), nullable=False, index=True)
    text: Mapped[str] = mapped_column(String(255), nullable=False)
    transcription: Mapped[str | None] = mapped_column(String(255), nullable=True)
    audio_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Роль (часть речи) В ЭТОМ ЯЗЫКЕ: pronoun, verb, noun, adjective, adverb,
    # preposition, number, other. Роль — свойство языка, а не понятия: одно и то
    # же понятие бывает глаголом в одном языке и существительным в другом, а
    # роли «предлог» в некоторых языках нет вовсе. Пусто -- берётся роль
    # понятия (Concept.role) как запасное значение.
    role: Mapped[str | None] = mapped_column(String(32), nullable=True)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    concept: Mapped["Concept"] = relationship(back_populates="entries")
    forms: Mapped[list["WordEntryForm"]] = relationship(
        back_populates="entry", cascade="all, delete-orphan", order_by="WordEntryForm.id"
    )


class WordEntryForm(Base):
    """Форма слова в конкретном языке (бывшие `word_forms`, структура та же)."""

    __tablename__ = "word_entry_forms"

    id: Mapped[int] = mapped_column(primary_key=True)
    word_entry_id: Mapped[int] = mapped_column(
        ForeignKey("word_entries.id", ondelete="CASCADE"), nullable=False, index=True
    )
    language: Mapped[str] = mapped_column(String(8), nullable=False)
    text: Mapped[str] = mapped_column(String(255), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    entry: Mapped["WordEntry"] = relationship(back_populates="forms")


class PhraseConcept(Base):
    """Смысл фразы, общий для языков. Фразы устроены как слова — одна модель."""

    __tablename__ = "phrase_concepts"

    id: Mapped[int] = mapped_column(primary_key=True)
    dictionary_id: Mapped[int] = mapped_column(
        ForeignKey("dictionaries.id", ondelete="CASCADE"), nullable=False, index=True
    )
    category_id: Mapped[int | None] = mapped_column(
        ForeignKey("phrase_categories.id", ondelete="SET NULL"), nullable=True, index=True
    )
    image_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    entries: Mapped[list["PhraseEntry"]] = relationship(
        back_populates="phrase_concept", cascade="all, delete-orphan", order_by="PhraseEntry.id"
    )


class PhraseEntry(Base):
    """Предложение на одном языке: текст, транскрипция, аудио."""

    __tablename__ = "phrase_entries"
    __table_args__ = (UniqueConstraint("phrase_concept_id", "language", name="uq_phrase_entry_concept_language"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    phrase_concept_id: Mapped[int] = mapped_column(
        ForeignKey("phrase_concepts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    language: Mapped[str] = mapped_column(String(8), nullable=False, index=True)
    text: Mapped[str] = mapped_column(String(1000), nullable=False)
    transcription: Mapped[str | None] = mapped_column(String(255), nullable=True)
    audio_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    phrase_concept: Mapped["PhraseConcept"] = relationship(back_populates="entries")
