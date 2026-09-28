"""add lesson pass statistics

Three nullable columns, nothing to backfill.

  word_attempts.lesson_id    the lesson an answer was given in (NULL for
                             quests and older rows)
  lessons.pass_started_at    when the current pass started
  lessons.pass_start_scores  each word's score at that moment

Together they let GET /lessons/{id}/pass/stats report how one pass went.

Revision ID: a2c8e4f6b1d3
Revises: f1b7c3d9e5a2
Create Date: 2026-09-28 18:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a2c8e4f6b1d3'
down_revision: Union[str, None] = 'f1b7c3d9e5a2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('word_attempts', sa.Column('lesson_id', sa.Integer(), nullable=True))
    op.create_foreign_key(
        'fk_word_attempts_lesson_id', 'word_attempts', 'lessons', ['lesson_id'], ['id'], ondelete='SET NULL'
    )
    op.create_index('ix_word_attempts_lesson_id', 'word_attempts', ['lesson_id'])
    op.add_column('lessons', sa.Column('pass_started_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('lessons', sa.Column('pass_start_scores', sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column('lessons', 'pass_start_scores')
    op.drop_column('lessons', 'pass_started_at')
    op.drop_index('ix_word_attempts_lesson_id', table_name='word_attempts')
    op.drop_constraint('fk_word_attempts_lesson_id', 'word_attempts', type_='foreignkey')
    op.drop_column('word_attempts', 'lesson_id')
