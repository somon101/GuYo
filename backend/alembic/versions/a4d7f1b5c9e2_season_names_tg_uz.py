"""season names in the Tajik and Uzbek interface

Revision ID: a4d7f1b5c9e2
Revises: f3c6e0a4b8d9
Create Date: 2026-10-12 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "a4d7f1b5c9e2"
down_revision: Union[str, None] = "f3c6e0a4b8d9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("seasons", sa.Column("name_tg", sa.String(length=255), nullable=True))
    op.add_column("seasons", sa.Column("name_uz", sa.String(length=255), nullable=True))


def downgrade() -> None:
    op.drop_column("seasons", "name_uz")
    op.drop_column("seasons", "name_tg")
