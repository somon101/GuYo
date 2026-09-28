"""add lesson pass word set

One nullable column, nothing to backfill.

  lessons.pass_word_ids  the words the current pass through a lesson
                         covers, frozen when the pass starts (POST
                         /lessons/{id}/pass) so every word goes through
                         every exercise of that pass. NULL keeps the old
                         "words below their level right now" behavior for
                         app versions that never start a pass.

Revision ID: f1b7c3d9e5a2
Revises: e6fa0c4b8d21
Create Date: 2026-09-28 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'f1b7c3d9e5a2'
down_revision: Union[str, None] = 'e6fa0c4b8d21'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('lessons', sa.Column('pass_word_ids', sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column('lessons', 'pass_word_ids')
