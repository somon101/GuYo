"""add word_translations, quizlet field

Revision ID: 276ef30e1b23
Revises: 1c0a1ed0aa06
Create Date: 2026-09-15 17:21:09.600358

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '276ef30e1b23'
down_revision: Union[str, None] = '1c0a1ed0aa06'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('word_translations',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('word_id', sa.Integer(), nullable=False),
    sa.Column('language', sa.String(length=8), nullable=False),
    sa.Column('text', sa.String(length=255), nullable=False),
    sa.Column('audio_key', sa.Text(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['word_id'], ['words.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('word_id', 'language', name='uq_word_translation_language')
    )
    op.create_index(op.f('ix_word_translations_word_id'), 'word_translations', ['word_id'], unique=False)
    op.add_column('words', sa.Column('quizlet', sa.String(length=500), nullable=True))

    # Data migration: move each existing words.translation (+ its audio)
    # into a word_translations row *before* the old columns are dropped.
    # The translation's language wasn't tracked explicitly before this
    # migration, so it's inferred from the dictionary's own language: the
    # opposite of Russian/English, defaulting to Russian for a Chinese (or
    # any other) source dictionary -- this matches every word created so
    # far, which were always English-or-Russian word <-> Russian-or-English
    # translation pairs.
    op.execute(
        """
        INSERT INTO word_translations (word_id, language, text, audio_key, created_at, updated_at)
        SELECT
            w.id,
            CASE WHEN d.language = 'ru' THEN 'en' ELSE 'ru' END,
            w.translation,
            w.translation_audio_key,
            w.created_at,
            w.updated_at
        FROM words w
        JOIN dictionaries d ON d.id = w.dictionary_id
        WHERE w.translation IS NOT NULL AND w.translation <> ''
        """
    )

    op.drop_column('words', 'translation_audio_key')
    op.drop_column('words', 'translation')


def downgrade() -> None:
    op.add_column('words', sa.Column('translation', sa.VARCHAR(length=255), autoincrement=False, nullable=True))
    op.add_column('words', sa.Column('translation_audio_key', sa.TEXT(), autoincrement=False, nullable=True))

    # Best-effort restore: pick one translation per word (arbitrary if a
    # word ended up with more than one language) back onto the Word row.
    op.execute(
        """
        UPDATE words w
        SET translation = t.text,
            translation_audio_key = t.audio_key
        FROM (
            SELECT DISTINCT ON (word_id) word_id, text, audio_key
            FROM word_translations
            ORDER BY word_id, id
        ) t
        WHERE t.word_id = w.id
        """
    )
    op.alter_column('words', 'translation', nullable=False, server_default='')
    op.alter_column('words', 'translation', server_default=None)

    op.drop_column('words', 'quizlet')
    op.drop_index(op.f('ix_word_translations_word_id'), table_name='word_translations')
    op.drop_table('word_translations')
