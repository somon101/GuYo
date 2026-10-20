"""Pre-lesson word check: the learner's own rating of a word, its done-mark
on a lesson and the two admin switches.

Revision ID: a4c6e8f0b2d5
Revises: f3b5d7f9a1c4
"""

import sqlalchemy as sa
from alembic import op

revision: str = "a4c6e8f0b2d5"
down_revision: str | None = "f3b5d7f9a1c4"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("word_attempts", sa.Column("self_rating", sa.String(length=8), nullable=True))
    op.add_column("lessons", sa.Column("check_done_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("learning_settings", sa.Column("check_enabled", sa.Boolean(), server_default="true", nullable=False))
    op.add_column(
        "learning_settings", sa.Column("check_skip_allowed", sa.Boolean(), server_default="true", nullable=False)
    )


def downgrade() -> None:
    op.drop_column("learning_settings", "check_skip_allowed")
    op.drop_column("learning_settings", "check_enabled")
    op.drop_column("lessons", "check_done_at")
    op.drop_column("word_attempts", "self_rating")
