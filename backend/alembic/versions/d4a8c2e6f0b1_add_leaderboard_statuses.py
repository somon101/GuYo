"""add leaderboard statuses

Revision ID: d4a8c2e6f0b1
Revises: c9e3f7a1b5d8
Create Date: 2026-10-01

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "d4a8c2e6f0b1"
down_revision: Union[str, None] = "c9e3f7a1b5d8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "status_emojis",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=64), nullable=False),
        sa.Column("image_key", sa.String(length=500), nullable=False),
        sa.Column("enabled", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("order", sa.Integer(), server_default="0", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "status_phrases",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("text", sa.String(length=60), nullable=False),
        sa.Column("enabled", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("order", sa.Integer(), server_default="0", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.add_column("users", sa.Column("status_emoji_id", sa.Integer(), nullable=True))
    op.add_column("users", sa.Column("status_phrase_id", sa.Integer(), nullable=True))
    op.create_foreign_key(
        "fk_users_status_emoji_id", "users", "status_emojis", ["status_emoji_id"], ["id"], ondelete="SET NULL"
    )
    op.create_foreign_key(
        "fk_users_status_phrase_id", "users", "status_phrases", ["status_phrase_id"], ["id"], ondelete="SET NULL"
    )


def downgrade() -> None:
    op.drop_constraint("fk_users_status_phrase_id", "users", type_="foreignkey")
    op.drop_constraint("fk_users_status_emoji_id", "users", type_="foreignkey")
    op.drop_column("users", "status_phrase_id")
    op.drop_column("users", "status_emoji_id")
    op.drop_table("status_phrases")
    op.drop_table("status_emojis")
