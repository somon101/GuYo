"""Word levels follow the memory model: word_levels.min_days

Existing levels get default day marks by their old order (lowest first):
0, 1, 3, 7, 30 days, then doubling.

Revision ID: e2a4c6e8f0b3
Revises: d1f3a5c7e9b2
"""

import sqlalchemy as sa
from alembic import op

revision: str = "e2a4c6e8f0b3"
down_revision: str | None = "d1f3a5c7e9b2"
branch_labels = None
depends_on = None

DEFAULT_DAYS = [0, 1, 3, 7, 30]


def upgrade() -> None:
    op.add_column("word_levels", sa.Column("min_days", sa.Float(), nullable=False, server_default="0"))
    bind = op.get_bind()
    rows = bind.execute(sa.text("SELECT id FROM word_levels ORDER BY min_points, id")).fetchall()
    for i, (level_id,) in enumerate(rows):
        days = DEFAULT_DAYS[i] if i < len(DEFAULT_DAYS) else DEFAULT_DAYS[-1] * 2 ** (i - len(DEFAULT_DAYS) + 1)
        bind.execute(sa.text("UPDATE word_levels SET min_days = :d WHERE id = :i"), {"d": days, "i": level_id})


def downgrade() -> None:
    op.drop_column("word_levels", "min_days")
