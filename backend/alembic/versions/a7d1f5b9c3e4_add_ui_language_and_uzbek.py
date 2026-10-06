"""interface language per user, Uzbek phrase translation

Revision ID: a7d1f5b9c3e4
Revises: f6c0e4a8b2d3
Create Date: 2026-10-07 18:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "a7d1f5b9c3e4"
down_revision: Union[str, None] = "f6c0e4a8b2d3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("ui_language", sa.String(length=8), server_default="ru", nullable=False))
    op.add_column("phrases", sa.Column("translation_uz", sa.String(length=1000), nullable=True))


def downgrade() -> None:
    op.drop_column("phrases", "translation_uz")
    op.drop_column("users", "ui_language")
