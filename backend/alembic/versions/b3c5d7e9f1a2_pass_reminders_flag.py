"""pass_settings.reminders_enabled

Revision ID: b3c5d7e9f1a2
Revises: a2b4c6d8e0f1
"""
import sqlalchemy as sa
from alembic import op

revision = "b3c5d7e9f1a2"
down_revision = "a2b4c6d8e0f1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("pass_settings", sa.Column("reminders_enabled", sa.Boolean(), nullable=False, server_default="true"))


def downgrade() -> None:
    op.drop_column("pass_settings", "reminders_enabled")
