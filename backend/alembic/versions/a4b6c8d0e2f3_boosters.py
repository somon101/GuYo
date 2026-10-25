"""The "x2" ticket: a held item, switch-on log, a chest prize and a doubled flag.

Revision ID: a4b6c8d0e2f3
Revises: f3a5b7c9d1e2
"""
import sqlalchemy as sa
from alembic import op

revision = "a4b6c8d0e2f3"
down_revision = "f3a5b7c9d1e2"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "user_boosters",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("minutes", sa.Integer, nullable=False),
        sa.Column("qty", sa.Integer, nullable=False, server_default="0"),
        sa.UniqueConstraint("user_id", "minutes", name="uq_user_booster_minutes"),
    )
    op.create_table(
        "booster_uses",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=False, index=True),
    )
    op.add_column("chest_types", sa.Column("booster_minutes", sa.Integer, nullable=False, server_default="0"))
    op.add_column("user_chests", sa.Column("doubled", sa.Boolean, nullable=False, server_default="false"))


def downgrade() -> None:
    op.drop_column("user_chests", "doubled")
    op.drop_column("chest_types", "booster_minutes")
    op.drop_table("booster_uses")
    op.drop_table("user_boosters")
