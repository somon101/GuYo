"""users.daily_goal and pass_settings.xp_daily_goal

Revision ID: c4d6e8f0a2b3
Revises: b3c5d7e9f1a2
"""
import sqlalchemy as sa
from alembic import op

revision = "c4d6e8f0a2b3"
down_revision = "b3c5d7e9f1a2"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("daily_goal", sa.Integer(), nullable=False, server_default="10"))
    op.add_column("pass_settings", sa.Column("xp_daily_goal", sa.Integer(), nullable=False, server_default="15"))


def downgrade() -> None:
    op.drop_column("pass_settings", "xp_daily_goal")
    op.drop_column("users", "daily_goal")
