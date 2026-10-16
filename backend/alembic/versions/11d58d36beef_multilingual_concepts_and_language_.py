"""multilingual concepts and language entries

Revision ID: 11d58d36beef
Revises: e5c1f8b40d27
Create Date: 2026-10-16 21:02:15.604751

Понятие + языковые записи: новая структура создаётся РЯДОМ со старой, данные
переносит отдельный этап (docs/multilingual-migration.md), поэтому здесь только
создание таблиц и НИ ОДНОЙ правки существующих.

Автогенерация попутно предлагала выставить NOT NULL у двух десятков колонок
чужих таблиц (`api_keys.created_at`, `mini_phrases.updated_at`, ...). Это её
известное ложное срабатывание: модель объявляет `Mapped[datetime]`, а в базе у
этих колонок уже есть NOT NULL -- сравнивать нечего. Такие правки здесь
намеренно выброшены: они ничего не улучшают, а на боевой базе могли бы упасть.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "11d58d36beef"
down_revision: Union[str, None] = "e5c1f8b40d27"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "concepts",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("dictionary_id", sa.Integer(), nullable=False),
        sa.Column("category_id", sa.Integer(), nullable=True),
        sa.Column("importance", sa.Integer(), server_default="3", nullable=False),
        sa.Column("role", sa.String(length=32), nullable=True),
        sa.Column("image_key", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["category_id"], ["categories.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["dictionary_id"], ["dictionaries.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_concepts_category_id"), "concepts", ["category_id"], unique=False)
    op.create_index(op.f("ix_concepts_dictionary_id"), "concepts", ["dictionary_id"], unique=False)

    op.create_table(
        "concept_topics",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("concept_id", sa.Integer(), nullable=False),
        sa.Column("topic", sa.String(length=32), nullable=False),
        sa.ForeignKeyConstraint(["concept_id"], ["concepts.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_concept_topics_concept_id"), "concept_topics", ["concept_id"], unique=False)

    op.create_table(
        "word_entries",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("concept_id", sa.Integer(), nullable=False),
        sa.Column("language", sa.String(length=8), nullable=False),
        sa.Column("text", sa.String(length=255), nullable=False),
        sa.Column("transcription", sa.String(length=255), nullable=True),
        sa.Column("audio_key", sa.Text(), nullable=True),
        sa.Column("enabled", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["concept_id"], ["concepts.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("concept_id", "language", name="uq_word_entry_concept_language"),
    )
    op.create_index(op.f("ix_word_entries_concept_id"), "word_entries", ["concept_id"], unique=False)
    op.create_index(op.f("ix_word_entries_language"), "word_entries", ["language"], unique=False)

    op.create_table(
        "word_entry_forms",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("word_entry_id", sa.Integer(), nullable=False),
        sa.Column("language", sa.String(length=8), nullable=False),
        sa.Column("text", sa.String(length=255), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["word_entry_id"], ["word_entries.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_word_entry_forms_word_entry_id"), "word_entry_forms", ["word_entry_id"], unique=False
    )

    op.create_table(
        "phrase_concepts",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("dictionary_id", sa.Integer(), nullable=False),
        sa.Column("category_id", sa.Integer(), nullable=True),
        sa.Column("image_key", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["category_id"], ["phrase_categories.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["dictionary_id"], ["dictionaries.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_phrase_concepts_category_id"), "phrase_concepts", ["category_id"], unique=False)
    op.create_index(op.f("ix_phrase_concepts_dictionary_id"), "phrase_concepts", ["dictionary_id"], unique=False)

    op.create_table(
        "phrase_entries",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("phrase_concept_id", sa.Integer(), nullable=False),
        sa.Column("language", sa.String(length=8), nullable=False),
        sa.Column("text", sa.String(length=1000), nullable=False),
        sa.Column("transcription", sa.String(length=255), nullable=True),
        sa.Column("audio_key", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["phrase_concept_id"], ["phrase_concepts.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("phrase_concept_id", "language", name="uq_phrase_entry_concept_language"),
    )
    op.create_index(op.f("ix_phrase_entries_language"), "phrase_entries", ["language"], unique=False)
    op.create_index(
        op.f("ix_phrase_entries_phrase_concept_id"), "phrase_entries", ["phrase_concept_id"], unique=False
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_phrase_entries_phrase_concept_id"), table_name="phrase_entries")
    op.drop_index(op.f("ix_phrase_entries_language"), table_name="phrase_entries")
    op.drop_table("phrase_entries")

    op.drop_index(op.f("ix_phrase_concepts_dictionary_id"), table_name="phrase_concepts")
    op.drop_index(op.f("ix_phrase_concepts_category_id"), table_name="phrase_concepts")
    op.drop_table("phrase_concepts")

    op.drop_index(op.f("ix_word_entry_forms_word_entry_id"), table_name="word_entry_forms")
    op.drop_table("word_entry_forms")

    op.drop_index(op.f("ix_word_entries_language"), table_name="word_entries")
    op.drop_index(op.f("ix_word_entries_concept_id"), table_name="word_entries")
    op.drop_table("word_entries")

    op.drop_index(op.f("ix_concept_topics_concept_id"), table_name="concept_topics")
    op.drop_table("concept_topics")

    op.drop_index(op.f("ix_concepts_dictionary_id"), table_name="concepts")
    op.drop_index(op.f("ix_concepts_category_id"), table_name="concepts")
    op.drop_table("concepts")
