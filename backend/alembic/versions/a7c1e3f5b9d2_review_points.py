"""Rating points for "Повторить сегодня"

Two settings on rating_settings (off by default, 5 points) and the
user_review_points ledger.

Revision ID: a7c1e3f5b9d2
Revises: f6a0b2c4d5e7
Create Date: 2026-10-11 12:00:00.000000
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "a7c1e3f5b9d2"
down_revision: Union[str, None] = "f6a0b2c4d5e7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("rating_settings", sa.Column("review_points_enabled", sa.Boolean(), server_default="false", nullable=False))
    op.add_column("rating_settings", sa.Column("review_points_per_correct", sa.Integer(), server_default="5", nullable=False))
    op.create_table(
        "user_review_points",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("word_id", sa.Integer(), nullable=False),
        sa.Column("points_awarded", sa.Integer(), nullable=False),
        sa.Column("awarded_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["word_id"], ["words.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_user_review_points_user_id", "user_review_points", ["user_id"])
    op.create_index("ix_user_review_points_word_id", "user_review_points", ["word_id"])


def downgrade() -> None:
    op.drop_index("ix_user_review_points_word_id", table_name="user_review_points")
    op.drop_index("ix_user_review_points_user_id", table_name="user_review_points")
    op.drop_table("user_review_points")
    op.drop_column("rating_settings", "review_points_per_correct")
    op.drop_column("rating_settings", "review_points_enabled")
