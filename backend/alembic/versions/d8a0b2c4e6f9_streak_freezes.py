"""Streak freezes: the stock on a user, the days they covered, the cap setting.

Revision ID: d8a0b2c4e6f9
Revises: c6e8f0a2b4d7
"""

import sqlalchemy as sa
from alembic import op

revision: str = "d8a0b2c4e6f9"
down_revision: str | None = "c6e8f0a2b4d7"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("streak_freezes", sa.Integer(), server_default="0", nullable=False))
    op.add_column("pass_settings", sa.Column("freeze_cap", sa.Integer(), server_default="3", nullable=False))
    op.create_table(
        "user_streak_freezes",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("covered_date", sa.Date(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("user_id", "covered_date", name="uq_user_streak_freeze_day"),
    )
    op.create_index("ix_user_streak_freezes_user_id", "user_streak_freezes", ["user_id"])


def downgrade() -> None:
    op.drop_table("user_streak_freezes")
    op.drop_column("pass_settings", "freeze_cap")
    op.drop_column("users", "streak_freezes")
