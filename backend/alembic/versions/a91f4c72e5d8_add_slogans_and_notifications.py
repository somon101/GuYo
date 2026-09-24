"""add slogans and notifications

Three new tables, nothing existing touched.

  slogans              the greeting lines an admin curates
  user_daily_slogans   which slogan each user drew on which day, so the
                       greeting holds still for a day and changes with it
  notifications        one inbox row per message, whatever created it

UNIQUE(user_id, shown_date) is what actually enforces "one slogan per user
per day"; UNIQUE(user_id, dedupe_key) is what will let a future automatic
rule call send_notification defensively without ever repeating itself.
dedupe_key is nullable and manual messages leave it NULL -- Postgres allows
any number of NULLs under a unique constraint, so an admin can send the
same text as often as they like.

Revision ID: a91f4c72e5d8
Revises: f7a3d19c0b42
Create Date: 2026-09-25 00:20:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a91f4c72e5d8'
down_revision: Union[str, None] = 'f7a3d19c0b42'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'slogans',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('text', sa.String(length=255), nullable=False),
        sa.Column('enabled', sa.Boolean(), server_default='true', nullable=False),
        sa.Column('order', sa.Integer(), server_default='0', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.PrimaryKeyConstraint('id'),
    )

    op.create_table(
        'user_daily_slogans',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('slogan_id', sa.Integer(), nullable=False),
        sa.Column('shown_date', sa.Date(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['slogan_id'], ['slogans.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'shown_date', name='uq_user_daily_slogan_once'),
    )
    op.create_index('ix_user_daily_slogans_user_id', 'user_daily_slogans', ['user_id'])
    op.create_index('ix_user_daily_slogans_slogan_id', 'user_daily_slogans', ['slogan_id'])

    op.create_table(
        'notifications',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('source', sa.String(length=64), server_default='manual', nullable=False),
        sa.Column('title', sa.String(length=120), nullable=True),
        sa.Column('body', sa.Text(), nullable=False),
        sa.Column('dedupe_key', sa.String(length=200), nullable=True),
        sa.Column('read_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'dedupe_key', name='uq_notification_dedupe_key'),
    )
    op.create_index('ix_notifications_user_id', 'notifications', ['user_id'])
    op.create_index('ix_notifications_created_at', 'notifications', ['created_at'])


def downgrade() -> None:
    op.drop_index('ix_notifications_created_at', table_name='notifications')
    op.drop_index('ix_notifications_user_id', table_name='notifications')
    op.drop_table('notifications')
    op.drop_index('ix_user_daily_slogans_slogan_id', table_name='user_daily_slogans')
    op.drop_index('ix_user_daily_slogans_user_id', table_name='user_daily_slogans')
    op.drop_table('user_daily_slogans')
    op.drop_table('slogans')
