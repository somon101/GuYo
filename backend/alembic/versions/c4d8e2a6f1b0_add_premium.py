"""add premium

Two new tables, nothing existing touched.

  premium_settings  one row: lesson limits for free and Premium users,
                    which automatic features are Premium-only, and the
                    price/payment text the app's Premium screen shows
  premium_grants    one paid period per row, kept as history -- Premium
                    is derived from these, never stored as a flag

The settings row is not seeded here: get_premium_settings creates it with
its defaults (3 lessons a day, 10 a week for free users; unlimited for
Premium; adaptive lessons and personal quests Premium-only) on first read,
the same way RatingSettings and PrioritySettings are.

Revision ID: c4d8e2a6f1b0
Revises: b7e2f4a91c33
Create Date: 2026-09-26 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c4d8e2a6f1b0'
down_revision: Union[str, None] = 'b7e2f4a91c33'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'premium_settings',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('free_daily_lesson_limit', sa.Integer(), server_default='3', nullable=True),
        sa.Column('free_weekly_lesson_limit', sa.Integer(), server_default='10', nullable=True),
        sa.Column('premium_daily_lesson_limit', sa.Integer(), nullable=True),
        sa.Column('premium_weekly_lesson_limit', sa.Integer(), nullable=True),
        sa.Column('adaptive_lessons_premium_only', sa.Boolean(), server_default='true', nullable=False),
        sa.Column('personal_quests_premium_only', sa.Boolean(), server_default='true', nullable=False),
        sa.Column('price_text', sa.String(length=200), server_default='', nullable=False),
        sa.Column('payment_instructions', sa.Text(), server_default='', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.CheckConstraint('free_daily_lesson_limit IS NULL OR free_daily_lesson_limit >= 0', name='ck_premium_free_daily'),
        sa.CheckConstraint('free_weekly_lesson_limit IS NULL OR free_weekly_lesson_limit >= 0', name='ck_premium_free_weekly'),
        sa.CheckConstraint(
            'premium_daily_lesson_limit IS NULL OR premium_daily_lesson_limit >= 0', name='ck_premium_premium_daily'
        ),
        sa.CheckConstraint(
            'premium_weekly_lesson_limit IS NULL OR premium_weekly_lesson_limit >= 0', name='ck_premium_premium_weekly'
        ),
        sa.PrimaryKeyConstraint('id'),
    )

    op.create_table(
        'premium_grants',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('starts_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('ends_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('days', sa.Integer(), nullable=False),
        sa.Column('source', sa.String(length=64), server_default='admin', nullable=False),
        sa.Column('note', sa.String(length=500), nullable=True),
        sa.Column('granted_by_admin_id', sa.Integer(), nullable=True),
        sa.Column('revoked_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['granted_by_admin_id'], ['admins.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_premium_grants_user_id', 'premium_grants', ['user_id'])
    op.create_index('ix_premium_grants_ends_at', 'premium_grants', ['ends_at'])


def downgrade() -> None:
    op.drop_index('ix_premium_grants_ends_at', table_name='premium_grants')
    op.drop_index('ix_premium_grants_user_id', table_name='premium_grants')
    op.drop_table('premium_grants')
    op.drop_table('premium_settings')
