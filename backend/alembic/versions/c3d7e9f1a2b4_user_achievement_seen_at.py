"""When a user was shown each earned achievement

Revision ID: c3d7e9f1a2b4
Revises: e2b5d9f3a7c8
Create Date: 2026-10-08 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "c3d7e9f1a2b4"
down_revision: Union[str, None] = "e2b5d9f3a7c8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("user_achievements", sa.Column("seen_at", sa.DateTime(timezone=True), nullable=True))
    # Everything earned before this existed counts as already shown, so no
    # one gets a burst of old celebrations after the update.
    op.execute("UPDATE user_achievements SET seen_at = earned_at")


def downgrade() -> None:
    op.drop_column("user_achievements", "seen_at")
