"""Catalog names in every interface language.

Revision ID: c6d8e0f2a4b5
Revises: b5c7d9e1f3a4
"""
import sqlalchemy as sa
from alembic import op

revision = "c6d8e0f2a4b5"
down_revision = "b5c7d9e1f3a4"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("cosmetic_defs", sa.Column("names", sa.JSON, nullable=True))
    bind = op.get_bind()
    t = sa.table("cosmetic_defs", sa.column("id", sa.Integer), sa.column("name_tg", sa.String), sa.column("name_uz", sa.String), sa.column("names", sa.JSON))
    for row in bind.execute(sa.select(t.c.id, t.c.name_tg, t.c.name_uz)).all():
        names = {k: v for k, v in (("tg", row.name_tg), ("uz", row.name_uz)) if v}
        bind.execute(sa.update(t).where(t.c.id == row.id).values(names=names))


def downgrade() -> None:
    op.drop_column("cosmetic_defs", "names")
