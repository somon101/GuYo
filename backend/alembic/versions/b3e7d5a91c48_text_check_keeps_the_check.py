"""Text checks keep the check itself: the text, the prompt and the answer

Every row in text_check_runs already said WHO checked and WHEN, and how long the
message was -- but not the message, what was asked of the model, or what it
answered. Those lived only in text_check_cache, which is keyed by the normalized
text and therefore cannot say which user asked for it.

These columns are what Admin Web's cards are built from: open one and see the text
as written, the prompt that produced the answer, and the whole answer.

Nullable on purpose: the checks recorded before this migration have only their
length, and a card that says so is better than an empty one.

Revision ID: b3e7d5a91c48
Revises: c4a9e1d7b2f5
Create Date: 2026-10-16

"""
from alembic import op
import sqlalchemy as sa

revision = "b3e7d5a91c48"
down_revision = "c4a9e1d7b2f5"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("text_check_runs", sa.Column("text", sa.Text(), nullable=True))
    op.add_column("text_check_runs", sa.Column("prompt", sa.Text(), nullable=True))
    op.add_column("text_check_runs", sa.Column("answer", sa.Text(), nullable=True))
    op.add_column("text_check_runs", sa.Column("params", sa.JSON(), nullable=True))
    op.add_column("text_check_runs", sa.Column("model", sa.String(length=64), nullable=True))
    op.add_column(
        "text_check_runs",
        sa.Column("user_login", sa.String(length=64), nullable=False, server_default=""),
    )


def downgrade() -> None:
    op.drop_column("text_check_runs", "user_login")
    op.drop_column("text_check_runs", "model")
    op.drop_column("text_check_runs", "params")
    op.drop_column("text_check_runs", "answer")
    op.drop_column("text_check_runs", "prompt")
    op.drop_column("text_check_runs", "text")
