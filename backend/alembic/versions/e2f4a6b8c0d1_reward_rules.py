"""Reward rules, daily-goal claims, once-only markers.

Revision ID: e2f4a6b8c0d1
Revises: d1e3f5a7b9c0
"""
import sqlalchemy as sa
from alembic import op

revision = "e2f4a6b8c0d1"
down_revision = "d1e3f5a7b9c0"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table("reward_rules", sa.Column("key", sa.String(32), primary_key=True), sa.Column("data", sa.JSON, nullable=False))
    op.create_table(
        "daily_goal_claims",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("day", sa.Date, nullable=False),
        sa.Column("words", sa.Integer, nullable=False),
        sa.UniqueConstraint("user_id", "day", "words", name="uq_daily_goal_claim"),
    )
    op.create_table(
        "reward_markers",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("key", sa.String(160), nullable=False),
        sa.UniqueConstraint("user_id", "key", name="uq_reward_marker"),
    )


def downgrade() -> None:
    op.drop_table("reward_markers")
    op.drop_table("daily_goal_claims")
    op.drop_table("reward_rules")
