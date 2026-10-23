"""virtual diamonds, gifts, shop products, and saved streak merges

Revision ID: f8c1d2e3a4b5
Revises: b9c1d3e5f7a8
"""

from alembic import op
import sqlalchemy as sa

revision = "f8c1d2e3a4b5"
down_revision = "b9c1d3e5f7a8"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("diamonds_balance", sa.Integer(), nullable=False, server_default="0"))
    op.add_column("users", sa.Column("streak_merge_items", sa.Integer(), nullable=False, server_default="0"))
    op.add_column("users", sa.Column("streak_merge_days", sa.Integer(), nullable=False, server_default="0"))
    op.add_column("users", sa.Column("streak_merge_cursor", sa.Date(), nullable=True))

    op.create_table(
        "diamond_transactions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("amount", sa.Integer(), nullable=False),
        sa.Column("source", sa.String(32), nullable=False),
        sa.Column("reference", sa.String(160), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("user_id", "reference", name="uq_diamond_transaction_reference"),
    )
    op.create_index("ix_diamond_transactions_user_id", "diamond_transactions", ["user_id"])

    op.create_table(
        "shop_products",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("sku", sa.String(64), nullable=False, unique=True),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("description", sa.Text(), nullable=False, server_default=""),
        sa.Column("item_type", sa.String(32), nullable=False),
        sa.Column("quantity", sa.Integer(), nullable=False),
        sa.Column("price_diamonds", sa.Integer(), nullable=False),
        sa.Column("icon_key", sa.String(32), nullable=False, server_default="gift"),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )

    op.create_table(
        "gift_definitions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("key", sa.String(64), nullable=False, unique=True),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("description", sa.Text(), nullable=False, server_default=""),
        sa.Column("icon_key", sa.String(32), nullable=False, server_default="gift"),
        sa.Column("reward_min", sa.Integer(), nullable=False),
        sa.Column("reward_max", sa.Integer(), nullable=False),
        sa.Column("cooldown_days", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("requires_activity", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_table(
        "gift_opens",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("gift_id", sa.Integer(), sa.ForeignKey("gift_definitions.id", ondelete="CASCADE"), nullable=False),
        sa.Column("opened_on", sa.Date(), nullable=False),
        sa.Column("kind", sa.String(24), nullable=False),
        sa.Column("amount", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("user_id", "gift_id", "opened_on", name="uq_gift_open_per_day"),
    )
    op.create_index("ix_gift_opens_user_id", "gift_opens", ["user_id"])
    op.create_index("ix_gift_opens_gift_id", "gift_opens", ["gift_id"])

    bind = op.get_bind()
    gift_id = 1
    op.bulk_insert(
        sa.table(
            "gift_definitions",
            sa.column("id", sa.Integer), sa.column("key", sa.String), sa.column("name", sa.String),
            sa.column("description", sa.Text), sa.column("icon_key", sa.String),
            sa.column("reward_min", sa.Integer), sa.column("reward_max", sa.Integer),
            sa.column("cooldown_days", sa.Integer), sa.column("requires_activity", sa.Boolean),
            sa.column("enabled", sa.Boolean), sa.column("sort_order", sa.Integer),
        ),
        [{"id": gift_id, "key": "daily-chest", "name": "Подарок дня", "description": "Откройте после занятия и получите бриллианты", "icon_key": "chest", "reward_min": 5, "reward_max": 25, "cooldown_days": 1, "requires_activity": True, "enabled": True, "sort_order": 0}],
    )
    op.execute(sa.text("SELECT setval(pg_get_serial_sequence('gift_definitions', 'id'), 1, true)"))
    op.bulk_insert(
        sa.table(
            "shop_products",
            sa.column("sku", sa.String), sa.column("name", sa.String), sa.column("description", sa.Text),
            sa.column("item_type", sa.String), sa.column("quantity", sa.Integer), sa.column("price_diamonds", sa.Integer),
            sa.column("icon_key", sa.String), sa.column("enabled", sa.Boolean), sa.column("sort_order", sa.Integer),
        ),
        [
            {"sku": "streak-freeze-1", "name": "1 заморозка серии", "description": "Защитит серию от одного пропущенного дня.", "item_type": "streak_freeze", "quantity": 1, "price_diamonds": 50, "icon_key": "freeze", "enabled": True, "sort_order": 1},
            {"sku": "streak-freeze-10", "name": "10 заморозок серии", "description": "Запас из десяти заморозок серии.", "item_type": "streak_freeze", "quantity": 10, "price_diamonds": 300, "icon_key": "freeze", "enabled": True, "sort_order": 2},
            {"sku": "streak-merge-1", "name": "Объединитель серии", "description": "Объединяет сохранённые дни активности в текущую серию.", "item_type": "streak_merge", "quantity": 1, "price_diamonds": 500, "icon_key": "flame_spark", "enabled": True, "sort_order": 3},
        ],
    )
    # Keep historical daily chests as already opened, so deploying this
    # feature cannot let anyone claim a second gift for the same day.
    bind.execute(
        sa.text("""INSERT INTO gift_opens (user_id, gift_id, opened_on, kind, amount, created_at)
            SELECT user_id, :gift_id, chest_date, kind, amount, opened_at FROM daily_chests
            ON CONFLICT (user_id, gift_id, opened_on) DO NOTHING"""),
        {"gift_id": gift_id},
    )


def downgrade() -> None:
    op.drop_index("ix_gift_opens_gift_id", table_name="gift_opens")
    op.drop_index("ix_gift_opens_user_id", table_name="gift_opens")
    op.drop_table("gift_opens")
    op.drop_table("gift_definitions")
    op.drop_table("shop_products")
    op.drop_index("ix_diamond_transactions_user_id", table_name="diamond_transactions")
    op.drop_table("diamond_transactions")
    op.drop_column("users", "streak_merge_cursor")
    op.drop_column("users", "streak_merge_days")
    op.drop_column("users", "streak_merge_items")
    op.drop_column("users", "diamonds_balance")
