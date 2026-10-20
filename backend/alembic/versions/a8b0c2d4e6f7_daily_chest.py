"""daily chests and their pass settings

Revision ID: a8b0c2d4e6f7
Revises: f7a9b1c3d5e6
"""
import sqlalchemy as sa
from alembic import op

revision = "a8b0c2d4e6f7"
down_revision = "f7a9b1c3d5e6"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "daily_chests",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("chest_date", sa.Date(), nullable=False),
        sa.Column("kind", sa.String(12), nullable=False),
        sa.Column("amount", sa.Integer(), nullable=False),
        sa.Column("opened_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("user_id", "chest_date", name="uq_daily_chest_once"),
    )
    op.create_index("ix_daily_chests_user_id", "daily_chests", ["user_id"])
    op.add_column("pass_settings", sa.Column("chest_enabled", sa.Boolean(), nullable=False, server_default="true"))
    op.add_column("pass_settings", sa.Column("chest_xp_min", sa.Integer(), nullable=False, server_default="10"))
    op.add_column("pass_settings", sa.Column("chest_xp_max", sa.Integer(), nullable=False, server_default="40"))
    op.add_column("pass_settings", sa.Column("chest_freeze_chance", sa.Integer(), nullable=False, server_default="5"))


def downgrade() -> None:
    for c in ("chest_freeze_chance", "chest_xp_max", "chest_xp_min", "chest_enabled"):
        op.drop_column("pass_settings", c)
    op.drop_table("daily_chests")
