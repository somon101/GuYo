"""Three kinds of "x2" tickets: chests, rating points, season-pass energy.

Revision ID: d7e9f1a3b5c6
Revises: c6d8e0f2a4b5
"""
import sqlalchemy as sa
from alembic import op

revision = "d7e9f1a3b5c6"
down_revision = "c6d8e0f2a4b5"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("user_boosters", sa.Column("kind", sa.String(8), nullable=False, server_default="chest"))
    op.add_column("booster_uses", sa.Column("kind", sa.String(8), nullable=False, server_default="chest"))
    op.drop_constraint("uq_user_booster_minutes", "user_boosters", type_="unique")
    op.create_unique_constraint("uq_user_booster_kind_minutes", "user_boosters", ["user_id", "kind", "minutes"])


def downgrade() -> None:
    op.drop_constraint("uq_user_booster_kind_minutes", "user_boosters", type_="unique")
    op.create_unique_constraint("uq_user_booster_minutes", "user_boosters", ["user_id", "minutes"])
    op.drop_column("booster_uses", "kind")
    op.drop_column("user_boosters", "kind")
