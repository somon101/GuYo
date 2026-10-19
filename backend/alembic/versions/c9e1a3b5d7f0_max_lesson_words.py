"""Admin-set maximum number of words in one lesson

Revision ID: c9e1a3b5d7f0
Revises: b7d9f1a3c5e8
"""

import sqlalchemy as sa
from alembic import op

revision: str = "c9e1a3b5d7f0"
down_revision: str | None = "b7d9f1a3c5e8"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "learning_settings",
        sa.Column("max_lesson_words", sa.Integer(), nullable=False, server_default="15"),
    )


def downgrade() -> None:
    op.drop_column("learning_settings", "max_lesson_words")
