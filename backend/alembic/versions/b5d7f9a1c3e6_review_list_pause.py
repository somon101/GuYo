"""«Повторить сегодня»: a pause (hours) between one list closing and the next opening.

Revision ID: b5d7f9a1c3e6
Revises: a4c6e8f0b2d5
"""

import sqlalchemy as sa
from alembic import op

revision: str = "b5d7f9a1c3e6"
down_revision: str | None = "a4c6e8f0b2d5"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "reminder_settings", sa.Column("review_list_pause_hours", sa.Integer(), server_default="12", nullable=False)
    )


def downgrade() -> None:
    op.drop_column("reminder_settings", "review_list_pause_hours")
