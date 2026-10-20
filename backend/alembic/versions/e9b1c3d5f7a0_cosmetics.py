"""Badges and titles earned in the season pass, and the ones a person wears.

Revision ID: e9b1c3d5f7a0
Revises: d8a0b2c4e6f9
"""

import sqlalchemy as sa
from alembic import op

revision: str = "e9b1c3d5f7a0"
down_revision: str | None = "d8a0b2c4e6f9"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "user_cosmetics",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("kind", sa.String(length=8), nullable=False),
        sa.Column("key", sa.String(length=32), server_default="", nullable=False),
        sa.Column("label", sa.String(length=120), nullable=False),
        sa.Column("label_tg", sa.String(length=120), nullable=True),
        sa.Column("label_uz", sa.String(length=120), nullable=True),
        sa.Column("season_id", sa.Integer(), sa.ForeignKey("seasons.id", ondelete="SET NULL"), nullable=True),
        sa.Column("season_name", sa.String(length=255), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("user_id", "kind", "key", "label", "season_id", name="uq_user_cosmetic_once"),
    )
    op.create_index("ix_user_cosmetics_user_id", "user_cosmetics", ["user_id"])
    op.add_column("users", sa.Column("equipped_badge_id", sa.Integer(), nullable=True))
    op.add_column("users", sa.Column("equipped_title_id", sa.Integer(), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "equipped_title_id")
    op.drop_column("users", "equipped_badge_id")
    op.drop_table("user_cosmetics")
