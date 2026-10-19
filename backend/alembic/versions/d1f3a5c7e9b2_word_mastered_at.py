"""Words become learned by mastery, not by score: word_progress.mastered_at

Backfill: every word that had reached the learned threshold under the old
score system is learned from now on (nobody loses a word).

Revision ID: d1f3a5c7e9b2
Revises: c9e1a3b5d7f0
"""

import sqlalchemy as sa
from alembic import op

revision: str = "d1f3a5c7e9b2"
down_revision: str | None = "c9e1a3b5d7f0"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("word_progress", sa.Column("mastered_at", sa.DateTime(timezone=True), nullable=True))
    op.create_index("ix_word_progress_mastered_at", "word_progress", ["mastered_at"])
    # The old "learned" threshold: the top enabled word level's min_points,
    # else the legacy learning_settings number, else 60 (app/exercises/common.py).
    op.execute(
        """
        UPDATE word_progress SET mastered_at = COALESCE(updated_at, now())
        WHERE mastered_at IS NULL AND score >= COALESCE(
            (SELECT min_points FROM word_levels WHERE enabled ORDER BY min_points DESC LIMIT 1),
            (SELECT threshold_score FROM learning_settings WHERE id = 1),
            60
        )
        """
    )


def downgrade() -> None:
    op.drop_index("ix_word_progress_mastered_at", table_name="word_progress")
    op.drop_column("word_progress", "mastered_at")
