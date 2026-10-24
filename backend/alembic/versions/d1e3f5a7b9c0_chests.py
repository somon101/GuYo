"""Chests: four types, a per-user bank, settings row.

Revision ID: d1e3f5a7b9c0
Revises: c0d2e4f6a8b9
"""
import sqlalchemy as sa
from alembic import op

revision = "d1e3f5a7b9c0"
down_revision = "c0d2e4f6a8b9"
branch_labels = None
depends_on = None

_TYPES = [
    ("wood", "Деревянный сундук", "#a0693b", 10, 1, 1, 20, 0),
    ("silver", "Серебряный сундук", "#5aa9e6", 30, 2, 2, 60, 1),
    ("purple", "Фиолетовый сундук", "#9b5de5", 100, 3, 3, 150, 2),
    ("gold", "Золотой сундук", "#f5b700", 300, 5, 5, 400, 3),
]


def upgrade() -> None:
    types = op.create_table(
        "chest_types",
        sa.Column("key", sa.String(16), primary_key=True),
        sa.Column("name", sa.String(80), nullable=False),
        sa.Column("color", sa.String(9), nullable=False, server_default="#9b6b3a"),
        sa.Column("max_diamonds", sa.Integer, nullable=False, server_default="0"),
        sa.Column("max_freezes", sa.Integer, nullable=False, server_default="0"),
        sa.Column("max_merges", sa.Integer, nullable=False, server_default="0"),
        sa.Column("max_points", sa.Integer, nullable=False, server_default="0"),
        sa.Column("sort_order", sa.Integer, nullable=False, server_default="0"),
    )
    op.bulk_insert(types, [
        dict(key=k, name=n, color=c, max_diamonds=d, max_freezes=f, max_merges=m, max_points=p, sort_order=s)
        for k, n, c, d, f, m, p, s in _TYPES
    ])
    op.create_table(
        "user_chests",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("chest_key", sa.String(16), nullable=False),
        sa.Column("source", sa.String(24), nullable=False),
        sa.Column("dedupe_key", sa.String(160)),
        sa.Column("granted_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False, index=True),
        sa.Column("opened_at", sa.DateTime(timezone=True)),
        sa.Column("prize_kind", sa.String(16)),
        sa.Column("prize_amount", sa.Integer),
        sa.Column("low_roll", sa.Boolean, nullable=False, server_default="false"),
        sa.UniqueConstraint("user_id", "dedupe_key", name="uq_user_chest_dedupe"),
    )
    settings = op.create_table(
        "chest_settings",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("daily_enabled", sa.Boolean, nullable=False, server_default="true"),
        sa.Column("daily_chest_key", sa.String(16), nullable=False, server_default="wood"),
        sa.Column("daily_requires_activity", sa.Boolean, nullable=False, server_default="true"),
        sa.Column("daily_conditions", sa.Text, nullable=False,
                  server_default="Сундук дня даётся один раз в сутки после первого занятия."),
        sa.Column("inventory_max", sa.Integer, nullable=False, server_default="10"),
        sa.Column("daily_cap", sa.Integer, nullable=False, server_default="10"),
        sa.Column("pity_after", sa.Integer, nullable=False, server_default="5"),
        sa.Column("double_until", sa.DateTime(timezone=True)),
    )
    op.bulk_insert(settings, [dict(id=1)])


def downgrade() -> None:
    op.drop_table("chest_settings")
    op.drop_table("user_chests")
    op.drop_table("chest_types")
