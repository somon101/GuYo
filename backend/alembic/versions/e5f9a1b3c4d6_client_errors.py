"""Errors reported by the mobile app

Revision ID: e5f9a1b3c4d6
Revises: d4e8f0a2b3c5
Create Date: 2026-10-10 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "e5f9a1b3c4d6"
down_revision: Union[str, None] = "d4e8f0a2b3c5"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "client_errors",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("app_build", sa.Integer(), nullable=True),
        sa.Column("platform", sa.String(length=32), nullable=True),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("stack", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_client_errors_user_id", "client_errors", ["user_id"])
    op.create_index("ix_client_errors_created_at", "client_errors", ["created_at"])


def downgrade() -> None:
    op.drop_index("ix_client_errors_created_at", table_name="client_errors")
    op.drop_index("ix_client_errors_user_id", table_name="client_errors")
    op.drop_table("client_errors")
