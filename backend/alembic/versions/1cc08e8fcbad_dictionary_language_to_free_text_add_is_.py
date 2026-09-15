"""dictionary language to free text, add is_published

Revision ID: 1cc08e8fcbad
Revises: 276ef30e1b23
Create Date: 2026-09-16 01:19:53.381561

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = '1cc08e8fcbad'
down_revision: Union[str, None] = '276ef30e1b23'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('dictionaries', sa.Column('is_published', sa.Boolean(), server_default='false', nullable=False))
    # Existing rows already hold 'en'/'ru'/'zh' -- those stay exactly as-is,
    # just no longer constrained to only those three values going forward.
    op.alter_column(
        'dictionaries', 'language',
        existing_type=postgresql.ENUM('en', 'ru', 'zh', name='dictionary_language'),
        type_=sa.String(length=64),
        existing_nullable=False,
        postgresql_using='language::text',
    )
    # The enum type itself is no longer referenced by any column; drop it
    # so it doesn't linger as dead schema.
    op.execute('DROP TYPE dictionary_language')


def downgrade() -> None:
    dictionary_language = postgresql.ENUM('en', 'ru', 'zh', name='dictionary_language')
    dictionary_language.create(op.get_bind())
    op.alter_column(
        'dictionaries', 'language',
        existing_type=sa.String(length=64),
        type_=dictionary_language,
        existing_nullable=False,
        postgresql_using='language::dictionary_language',
    )
    op.drop_column('dictionaries', 'is_published')
