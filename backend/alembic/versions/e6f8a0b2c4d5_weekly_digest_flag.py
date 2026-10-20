"""reminder_settings.weekly_digest_enabled

Revision ID: e6f8a0b2c4d5
Revises: d5e7f9a1b3c4
"""
import sqlalchemy as sa
from alembic import op

revision = "e6f8a0b2c4d5"
down_revision = "d5e7f9a1b3c4"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "reminder_settings", sa.Column("weekly_digest_enabled", sa.Boolean(), nullable=False, server_default="true")
    )


def downgrade() -> None:
    op.drop_column("reminder_settings", "weekly_digest_enabled")
