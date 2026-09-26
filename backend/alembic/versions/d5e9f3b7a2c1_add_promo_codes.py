"""add promo codes and promo links

Three new tables and two new columns on premium_settings.

  promo_codes        admin-made codes worth a fixed number of Premium days
  promo_links        links to GuYo's own videos, matched by normalized_key
  promo_activations  who activated what; UNIQUE per (user, code) and per
                     (user, link) is what enforces "once per user"

premium_settings gains promo_link_first_days / promo_link_repeat_days: a
user's first link is worth the first, every later link the second (unless
that link sets its own repeat_days).

Revision ID: d5e9f3b7a2c1
Revises: c4d8e2a6f1b0
Create Date: 2026-09-26 18:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd5e9f3b7a2c1'
down_revision: Union[str, None] = 'c4d8e2a6f1b0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('premium_settings', sa.Column('promo_link_first_days', sa.Integer(), server_default='90', nullable=False))
    op.add_column('premium_settings', sa.Column('promo_link_repeat_days', sa.Integer(), server_default='5', nullable=False))
    op.create_check_constraint('ck_premium_promo_first_days', 'premium_settings', 'promo_link_first_days > 0')
    op.create_check_constraint('ck_premium_promo_repeat_days', 'premium_settings', 'promo_link_repeat_days > 0')

    op.create_table(
        'promo_codes',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('code', sa.String(length=40), nullable=False),
        sa.Column('days', sa.Integer(), nullable=False),
        sa.Column('enabled', sa.Boolean(), server_default='true', nullable=False),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('max_activations', sa.Integer(), nullable=True),
        sa.Column('note', sa.String(length=300), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.CheckConstraint('days > 0', name='ck_promo_code_days_positive'),
        sa.CheckConstraint('max_activations IS NULL OR max_activations > 0', name='ck_promo_code_max_positive'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_promo_codes_code', 'promo_codes', ['code'], unique=True)

    op.create_table(
        'promo_links',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('url', sa.String(length=1000), nullable=False),
        sa.Column('normalized_key', sa.String(length=1000), nullable=False),
        sa.Column('title', sa.String(length=200), nullable=True),
        sa.Column('repeat_days', sa.Integer(), nullable=True),
        sa.Column('enabled', sa.Boolean(), server_default='true', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.CheckConstraint('repeat_days IS NULL OR repeat_days > 0', name='ck_promo_link_days_positive'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_promo_links_normalized_key', 'promo_links', ['normalized_key'], unique=True)

    op.create_table(
        'promo_activations',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('promo_code_id', sa.Integer(), nullable=True),
        sa.Column('promo_link_id', sa.Integer(), nullable=True),
        sa.Column('days', sa.Integer(), nullable=False),
        sa.Column('is_first_link', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('grant_id', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['promo_code_id'], ['promo_codes.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['promo_link_id'], ['promo_links.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['grant_id'], ['premium_grants.id'], ondelete='SET NULL'),
        sa.CheckConstraint('(promo_code_id IS NULL) <> (promo_link_id IS NULL)', name='ck_promo_activation_exactly_one'),
        sa.UniqueConstraint('user_id', 'promo_code_id', name='uq_promo_activation_user_code'),
        sa.UniqueConstraint('user_id', 'promo_link_id', name='uq_promo_activation_user_link'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_promo_activations_user_id', 'promo_activations', ['user_id'])
    op.create_index('ix_promo_activations_promo_code_id', 'promo_activations', ['promo_code_id'])
    op.create_index('ix_promo_activations_promo_link_id', 'promo_activations', ['promo_link_id'])
    op.create_index('ix_promo_activations_created_at', 'promo_activations', ['created_at'])


def downgrade() -> None:
    op.drop_index('ix_promo_activations_created_at', table_name='promo_activations')
    op.drop_index('ix_promo_activations_promo_link_id', table_name='promo_activations')
    op.drop_index('ix_promo_activations_promo_code_id', table_name='promo_activations')
    op.drop_index('ix_promo_activations_user_id', table_name='promo_activations')
    op.drop_table('promo_activations')
    op.drop_index('ix_promo_links_normalized_key', table_name='promo_links')
    op.drop_table('promo_links')
    op.drop_index('ix_promo_codes_code', table_name='promo_codes')
    op.drop_table('promo_codes')
    op.drop_constraint('ck_premium_promo_repeat_days', 'premium_settings', type_='check')
    op.drop_constraint('ck_premium_promo_first_days', 'premium_settings', type_='check')
    op.drop_column('premium_settings', 'promo_link_repeat_days')
    op.drop_column('premium_settings', 'promo_link_first_days')
