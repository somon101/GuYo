"""achievement title/description translations (tg, uz)

Revision ID: d8a2b4c6e1f3
Revises: c7f1a3e9d2b6
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "d8a2b4c6e1f3"
down_revision: str | None = "c7f1a3e9d2b6"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("achievements", sa.Column("title_tg", sa.String(255), nullable=True))
    op.add_column("achievements", sa.Column("title_uz", sa.String(255), nullable=True))
    op.add_column("achievements", sa.Column("description_tg", sa.String(500), nullable=True))
    op.add_column("achievements", sa.Column("description_uz", sa.String(500), nullable=True))


def downgrade() -> None:
    for col in ("description_uz", "description_tg", "title_uz", "title_tg"):
        op.drop_column("achievements", col)
