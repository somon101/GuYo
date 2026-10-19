"""Drop the sync journal: lessons are played online only again

Revision ID: f2b4d6a8c0e1
Revises: e3c5a7b9d1f2
"""

import sqlalchemy as sa
from alembic import op

revision: str = "f2b4d6a8c0e1"
down_revision: str | None = "e3c5a7b9d1f2"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("DROP TABLE IF EXISTS sync_journal")


def downgrade() -> None:
    op.create_table(
        "sync_journal",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=True),
        sa.Column("user_login", sa.String(64), nullable=True),
        sa.Column("lesson_id", sa.Integer(), nullable=True),
        sa.Column("action", sa.String(16), nullable=False),
        sa.Column("exercise_key", sa.String(64), nullable=True),
        sa.Column("word_id", sa.Integer(), nullable=True),
        sa.Column("payload", sa.JSON(), nullable=True),
        sa.Column("accepted", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("outcome", sa.String(255), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
