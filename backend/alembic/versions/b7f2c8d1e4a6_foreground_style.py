"""notification foreground style (the app's own banner or a system notification)

Revision ID: b7f2c8d1e4a6
Revises: f2d8c4a6b1e9
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "b7f2c8d1e4a6"
down_revision: str | None = "f2d8c4a6b1e9"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "reminder_settings",
        sa.Column("foreground_style", sa.String(16), nullable=False, server_default="banner"),
    )


def downgrade() -> None:
    op.drop_column("reminder_settings", "foreground_style")
