"""add category icon

Revision ID: b71c93af2d10
Revises: f45697cd04e3
Create Date: 2026-09-24 04:10:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b71c93af2d10'
down_revision: Union[str, None] = 'f45697cd04e3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('categories', sa.Column('icon_key', sa.String(length=512), nullable=True))


def downgrade() -> None:
    op.drop_column('categories', 'icon_key')
