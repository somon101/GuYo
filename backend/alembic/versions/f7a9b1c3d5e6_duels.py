"""duels, and the pass settings for them

Revision ID: f7a9b1c3d5e6
Revises: e6f8a0b2c4d5
"""
import sqlalchemy as sa
from alembic import op

revision = "f7a9b1c3d5e6"
down_revision = "e6f8a0b2c4d5"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "duels",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("challenger_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("opponent_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("week_start", sa.Date(), nullable=False),
        sa.Column("status", sa.String(12), nullable=False, server_default="pending"),
        sa.Column("winner_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("challenger_xp", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("opponent_xp", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_duels_challenger_id", "duels", ["challenger_id"])
    op.create_index("ix_duels_opponent_id", "duels", ["opponent_id"])
    op.create_index("ix_duels_status", "duels", ["status"])
    op.add_column("pass_settings", sa.Column("duels_enabled", sa.Boolean(), nullable=False, server_default="true"))
    op.add_column("pass_settings", sa.Column("xp_duel_win", sa.Integer(), nullable=False, server_default="50"))


def downgrade() -> None:
    op.drop_column("pass_settings", "xp_duel_win")
    op.drop_column("pass_settings", "duels_enabled")
    op.drop_table("duels")
