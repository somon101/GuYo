"""The sync journal: every packet a device sends to sync a lesson pass

Revision ID: c8f4a9e2d715
Revises: b3e7d5a91c48
Create Date: 2026-10-16

"""
from alembic import op
import sqlalchemy as sa

revision = "c8f4a9e2d715"
down_revision = "b3e7d5a91c48"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "sync_journal",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=True),
        sa.Column("user_login", sa.String(length=64), nullable=False, server_default=""),
        sa.Column("lesson_id", sa.Integer(), nullable=True),
        sa.Column("action", sa.String(length=16), nullable=False),
        sa.Column("exercise_key", sa.String(length=64), nullable=True),
        sa.Column("word_id", sa.Integer(), nullable=True),
        sa.Column("payload", sa.JSON(), nullable=True),
        sa.Column("accepted", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("outcome", sa.String(length=255), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["lesson_id"], ["lessons.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_sync_journal_user_id", "sync_journal", ["user_id"])
    op.create_index("ix_sync_journal_lesson_id", "sync_journal", ["lesson_id"])
    op.create_index("ix_sync_journal_action", "sync_journal", ["action"])
    op.create_index("ix_sync_journal_created_at", "sync_journal", ["created_at"])


def downgrade() -> None:
    op.drop_index("ix_sync_journal_created_at", table_name="sync_journal")
    op.drop_index("ix_sync_journal_action", table_name="sync_journal")
    op.drop_index("ix_sync_journal_lesson_id", table_name="sync_journal")
    op.drop_index("ix_sync_journal_user_id", table_name="sync_journal")
    op.drop_table("sync_journal")
