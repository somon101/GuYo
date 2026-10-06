"""AI translator key and progress

Revision ID: b8e2a6c0d4f5
Revises: a7d1f5b9c3e4
Create Date: 2026-10-06 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "b8e2a6c0d4f5"
down_revision: Union[str, None] = "a7d1f5b9c3e4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

COLUMNS = ("deepseek_api_key", "translate_status", "translate_total", "translate_done", "translate_failed", "translate_error")


def upgrade() -> None:
    op.add_column("learning_settings", sa.Column("deepseek_api_key", sa.Text(), nullable=True))
    op.add_column("learning_settings", sa.Column("translate_status", sa.String(length=16), server_default="idle", nullable=False))
    for name in ("translate_total", "translate_done", "translate_failed"):
        op.add_column("learning_settings", sa.Column(name, sa.Integer(), server_default="0", nullable=False))
    op.add_column("learning_settings", sa.Column("translate_error", sa.Text(), nullable=True))


def downgrade() -> None:
    for name in reversed(COLUMNS):
        op.drop_column("learning_settings", name)
