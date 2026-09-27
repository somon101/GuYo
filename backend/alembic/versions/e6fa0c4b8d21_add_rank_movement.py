"""add rank movement tracking

One new table and one new setting.

  user_rank_positions  each user's last-seen place in their own rank, the
                       place before their latest move and when it
                       happened (the "↑3 / ↓2" arrows), and the place they
                       were last notified about
  rating_settings.rank_move_notify_threshold
                       moving this many places sends a notification;
                       0 turns them off

Nothing to backfill: the first sync after deploy records everyone's
current place as their starting point, with no arrows and no
notifications.

Revision ID: e6fa0c4b8d21
Revises: f6b3d8a1c452
Create Date: 2026-09-27 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e6fa0c4b8d21'
down_revision: Union[str, None] = 'f6b3d8a1c452'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'rating_settings',
        sa.Column('rank_move_notify_threshold', sa.Integer(), server_default='5', nullable=False),
    )
    op.create_table(
        'user_rank_positions',
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('rank_id', sa.Integer(), nullable=True),
        sa.Column('position', sa.Integer(), nullable=False),
        sa.Column('previous_position', sa.Integer(), nullable=True),
        sa.Column('changed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('notified_position', sa.Integer(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['rank_id'], ['ranks.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('user_id'),
    )


def downgrade() -> None:
    op.drop_table('user_rank_positions')
    op.drop_column('rating_settings', 'rank_move_notify_threshold')
