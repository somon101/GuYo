"""users.token_version for "log out on other devices"

Revision ID: a2b4c6d8e0f1
Revises: f1d3e5a7b9c2
"""
import sqlalchemy as sa
from alembic import op

revision = "a2b4c6d8e0f1"
down_revision = "f1d3e5a7b9c2"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("token_version", sa.Integer(), nullable=False, server_default="0"))


def downgrade() -> None:
    op.drop_column("users", "token_version")
