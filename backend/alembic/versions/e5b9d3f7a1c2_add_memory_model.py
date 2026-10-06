"""add the memory model's data

  word_attempts.source       lesson / quest / practice
  word_attempts.duration_ms  time on screen before answering (from the app)
  word_attempts.timed_out    the countdown ran out
  word_progress.memory_*     FSRS stability / difficulty / last review /
                             number of review days, rebuilt from history

Revision ID: e5b9d3f7a1c2
Revises: d4a8c2e6f0b1
Create Date: 2026-10-07 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "e5b9d3f7a1c2"
down_revision: Union[str, None] = "d4a8c2e6f0b1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("word_attempts", sa.Column("source", sa.String(length=16), server_default="lesson", nullable=False))
    # Older rows keep the default: which of them were quest answers can't be
    # told apart reliably (lesson_id itself is newer than many of them).
    op.add_column("word_attempts", sa.Column("duration_ms", sa.Integer(), nullable=True))
    op.add_column("word_attempts", sa.Column("timed_out", sa.Boolean(), server_default="false", nullable=False))
    op.add_column("word_progress", sa.Column("memory_stability", sa.Float(), nullable=True))
    op.add_column("word_progress", sa.Column("memory_difficulty", sa.Float(), nullable=True))
    op.add_column("word_progress", sa.Column("memory_last_review", sa.DateTime(timezone=True), nullable=True))
    op.add_column("word_progress", sa.Column("memory_review_days", sa.Integer(), server_default="0", nullable=False))


def downgrade() -> None:
    for col in ("memory_review_days", "memory_last_review", "memory_difficulty", "memory_stability"):
        op.drop_column("word_progress", col)
    for col in ("timed_out", "duration_ms", "source"):
        op.drop_column("word_attempts", col)
