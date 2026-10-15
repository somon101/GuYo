"""The adaptive-lesson threshold becomes an admin number

How many "critical" words must accumulate before an adaptive lesson is built was
hardcoded at 5 (the spec's own example). It is now PrioritySettings.
adaptive_lesson_min_words, editable in Admin Web, defaulting to the same 5.

Revision ID: e5c1f8b40d27
Revises: d1b6a7e3c920
Create Date: 2026-10-16

"""
from alembic import op
import sqlalchemy as sa

revision = "e5c1f8b40d27"
down_revision = "d1b6a7e3c920"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "priority_settings",
        sa.Column("adaptive_lesson_min_words", sa.Integer(), nullable=False, server_default="5"),
    )


def downgrade() -> None:
    op.drop_column("priority_settings", "adaptive_lesson_min_words")
