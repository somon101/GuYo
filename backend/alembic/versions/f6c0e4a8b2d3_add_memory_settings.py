"""memory model settings on priority_settings (on by default)

Revision ID: f6c0e4a8b2d3
Revises: e5b9d3f7a1c2
Create Date: 2026-10-07 15:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "f6c0e4a8b2d3"
down_revision: Union[str, None] = "e5b9d3f7a1c2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

COLUMNS = [
    ("memory_enabled", sa.Boolean(), "true"),
    ("memory_target_retention", sa.Float(), "0.9"),
    ("memory_critical_below", sa.Float(), "0.7"),
    ("memory_high_below", sa.Float(), "0.85"),
    ("memory_minimal_above", sa.Float(), "0.95"),
]


def upgrade() -> None:
    for name, type_, default in COLUMNS:
        op.add_column("priority_settings", sa.Column(name, type_, server_default=default, nullable=False))


def downgrade() -> None:
    for name, _, _ in COLUMNS:
        op.drop_column("priority_settings", name)
