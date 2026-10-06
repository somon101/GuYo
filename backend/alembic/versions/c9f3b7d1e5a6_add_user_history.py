"""user history: the given answer on each attempt, and non-answer events

Revision ID: c9f3b7d1e5a6
Revises: b8e2a6c0d4f5
Create Date: 2026-10-07 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "c9f3b7d1e5a6"
down_revision: Union[str, None] = "b8e2a6c0d4f5"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("word_attempts", sa.Column("given_answer", sa.String(length=255), nullable=True))
    op.create_table(
        "user_events",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("kind", sa.String(length=32), nullable=False),
        sa.Column("lesson_id", sa.Integer(), sa.ForeignKey("lessons.id", ondelete="SET NULL"), nullable=True),
        sa.Column("quest_id", sa.Integer(), sa.ForeignKey("quests.id", ondelete="SET NULL"), nullable=True),
        sa.Column("data", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=True),
    )
    op.create_index("ix_user_events_user_created", "user_events", ["user_id", "created_at"])


def downgrade() -> None:
    op.drop_index("ix_user_events_user_created", table_name="user_events")
    op.drop_table("user_events")
    op.drop_column("word_attempts", "given_answer")
