"""text check (AI grammar checker): settings, run journal, answer cache

Revision ID: f2d8c4a6b1e9
Revises: d8a2b4c6e1f3
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "f2d8c4a6b1e9"
down_revision: str | None = "d8a2b4c6e1f3"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "text_check_settings",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("max_chars", sa.Integer(), nullable=False, server_default="500"),
        sa.Column("free_daily_limit", sa.Integer(), nullable=True, server_default="5"),
        sa.Column("premium_daily_limit", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.CheckConstraint("max_chars >= 1", name="ck_text_check_max_chars"),
        sa.CheckConstraint("free_daily_limit IS NULL OR free_daily_limit >= 0", name="ck_text_check_free_daily"),
        sa.CheckConstraint(
            "premium_daily_limit IS NULL OR premium_daily_limit >= 0", name="ck_text_check_premium_daily"
        ),
    )

    op.create_table(
        "text_check_runs",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("chars", sa.Integer(), nullable=False),
        sa.Column("cached", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("succeeded", sa.Boolean(), nullable=False, server_default="true"),
    )
    op.create_index("ix_text_check_runs_user_id", "text_check_runs", ["user_id"])
    op.create_index("ix_text_check_runs_created_at", "text_check_runs", ["created_at"])
    op.create_index("ix_text_check_runs_user_created", "text_check_runs", ["user_id", "created_at"])

    op.create_table(
        "text_check_cache",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("fingerprint", sa.String(64), nullable=False),
        sa.Column("text", sa.String(2000), nullable=False),
        sa.Column("params", sa.JSON(), nullable=False),
        sa.Column("result", sa.JSON(), nullable=False),
        sa.Column("hits", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_text_check_cache_fingerprint", "text_check_cache", ["fingerprint"], unique=True)

    op.add_column("users", sa.Column("text_check_unlimited", sa.Boolean(), nullable=False, server_default="false"))


def downgrade() -> None:
    op.drop_column("users", "text_check_unlimited")
    op.drop_index("ix_text_check_cache_fingerprint", table_name="text_check_cache")
    op.drop_table("text_check_cache")
    op.drop_index("ix_text_check_runs_user_created", table_name="text_check_runs")
    op.drop_index("ix_text_check_runs_created_at", table_name="text_check_runs")
    op.drop_index("ix_text_check_runs_user_id", table_name="text_check_runs")
    op.drop_table("text_check_runs")
    op.drop_table("text_check_settings")
