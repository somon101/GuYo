"""rebuild every memory state under the gentler day grade

Clears the stored memory state; the scheduler's rebuild_pending_memories
(app/memory/service.py) replays each pair's whole answer history again in
batches, now with the new day_grade. Nothing is lost: history is kept.

Revision ID: b5e8c2d6f0a3
Revises: a3d7f0c62e19
Create Date: 2026-10-19 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op


revision: str = "b5e8c2d6f0a3"
down_revision: Union[str, None] = "a3d7f0c62e19"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        "UPDATE word_progress SET memory_stability = NULL, memory_difficulty = NULL, "
        "memory_last_review = NULL, memory_review_days = 0"
    )


def downgrade() -> None:
    pass
