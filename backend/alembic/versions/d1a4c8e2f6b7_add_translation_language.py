"""translation language for Russian-interface users

Revision ID: d1a4c8e2f6b7
Revises: c9f3b7d1e5a6
Create Date: 2026-10-07 18:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "d1a4c8e2f6b7"
down_revision: Union[str, None] = "c9f3b7d1e5a6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("translation_language", sa.String(length=8), server_default="tg", nullable=False))
    # Uzbek-interface users already read Uzbek.
    op.execute("UPDATE users SET translation_language = 'uz' WHERE ui_language = 'uz'")


def downgrade() -> None:
    op.drop_column("users", "translation_language")
