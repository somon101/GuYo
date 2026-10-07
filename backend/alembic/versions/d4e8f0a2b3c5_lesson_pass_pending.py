"""Scores a lesson pass is still holding back

Revision ID: d4e8f0a2b3c5
Revises: c3d7e9f1a2b4
Create Date: 2026-10-08 13:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "d4e8f0a2b3c5"
down_revision: Union[str, None] = "c3d7e9f1a2b4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("lessons", sa.Column("pass_pending_scores", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("lessons", "pass_pending_scores")
