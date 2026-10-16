"""languages -- the platform's languages as data, not as code

Revision ID: 4b8e2f61c7a3
Revises: 7c3b5e91a204
Create Date: 2026-10-17 00:40:00.000000

До этой таблицы языки были зашиты в код. Теперь язык -- строка в базе, и его
можно завести из админки без программиста: у понятий появится ещё один слой
записей. Существующие языки (ru, tg, uz, en, zh) дописывает seed при запуске
сервиса -- он идемпотентен.

Написана вручную: автогенерация Alembic вместе с новыми таблицами снова
предлагает ложные правки NOT NULL у чужих колонок (см. 11d58d36beef).
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "4b8e2f61c7a3"
down_revision: Union[str, None] = "7c3b5e91a204"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "languages",
        sa.Column("code", sa.String(length=8), nullable=False),
        sa.Column("name", sa.String(length=64), nullable=False),
        sa.Column("native_name", sa.String(length=64), nullable=True),
        sa.Column("alphabet", sa.String(length=256), nullable=True),
        sa.Column("is_enabled", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("sort_order", sa.Integer(), server_default="0", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.PrimaryKeyConstraint("code"),
    )


def downgrade() -> None:
    op.drop_table("languages")
