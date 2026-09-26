"""add registration profile fields

Revision ID: f6b3d8a1c452
Revises: e1a4c9f2d7b3
Create Date: 2026-09-26 23:00:00.000000

Four new nullable columns on users, collected once during self-
registration and never required afterwards -- null on any account made
another way (an admin-created one, or one predating this feature). Plain
strings, same convention as Notification.source/PremiumGrant.source.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'f6b3d8a1c452'
down_revision: Union[str, None] = 'e1a4c9f2d7b3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('users', sa.Column('learning_language', sa.String(length=16), nullable=True))
    op.add_column('users', sa.Column('age_group', sa.String(length=32), nullable=True))
    op.add_column('users', sa.Column('learning_goal', sa.String(length=32), nullable=True))
    op.add_column('users', sa.Column('referral_source', sa.String(length=32), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'referral_source')
    op.drop_column('users', 'learning_goal')
    op.drop_column('users', 'age_group')
    op.drop_column('users', 'learning_language')
