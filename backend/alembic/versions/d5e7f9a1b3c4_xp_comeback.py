"""pass_settings.xp_comeback

Revision ID: d5e7f9a1b3c4
Revises: c4d6e8f0a2b3
"""
import sqlalchemy as sa
from alembic import op

revision = "d5e7f9a1b3c4"
down_revision = "c4d6e8f0a2b3"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("pass_settings", sa.Column("xp_comeback", sa.Integer(), nullable=False, server_default="20"))


def downgrade() -> None:
    op.drop_column("pass_settings", "xp_comeback")
