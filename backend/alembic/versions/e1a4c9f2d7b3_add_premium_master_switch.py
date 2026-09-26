"""add premium master switch

Revision ID: e1a4c9f2d7b3
Revises: d5e9f3b7a2c1
Create Date: 2026-09-26 22:00:00.000000

One boolean, default True (nothing changes for anyone until an admin
flips it): while False, the whole Premium system is suppressed
everywhere -- lesson limits, the two *_premium_only feature gates, and
every user-facing "is this person Premium" signal -- without touching a
single PremiumGrant row (see app/models/premium.py's own docstring).
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e1a4c9f2d7b3'
down_revision: Union[str, None] = 'd5e9f3b7a2c1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('premium_settings', sa.Column('premium_enabled', sa.Boolean(), server_default='true', nullable=False))


def downgrade() -> None:
    op.drop_column('premium_settings', 'premium_enabled')
