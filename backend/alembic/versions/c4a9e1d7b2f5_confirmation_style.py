"""notification confirmation style (the app's own floating card or the quiet pill)

Revision ID: c4a9e1d7b2f5
Revises: b7f2c8d1e4a6
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "c4a9e1d7b2f5"
down_revision: str | None = "b7f2c8d1e4a6"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "reminder_settings",
        sa.Column("confirmation_style", sa.String(16), nullable=False, server_default="banner"),
    )


def downgrade() -> None:
    op.drop_column("reminder_settings", "confirmation_style")
