"""Удаление аккаунта: users.deleted_at

Отметка «аккаунт удалён». Строка остаётся на месте, чтобы человек мог
передумать и войти снова в течение 30 дней; после этого её окончательно
удаляет python -m app.account_deletion purge.

Revision ID: b7d1e4a9c310
Revises: 4b8e2f61c7a3
"""

from alembic import op
import sqlalchemy as sa

revision = "b7d1e4a9c310"
down_revision = "4b8e2f61c7a3"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    columns = {c["name"] for c in sa.inspect(bind).get_columns("users")}
    if "deleted_at" not in columns:
        op.add_column("users", sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True))
    indexes = {i["name"] for i in sa.inspect(bind).get_indexes("users")}
    if "ix_users_deleted_at" not in indexes:
        op.create_index("ix_users_deleted_at", "users", ["deleted_at"])


def downgrade() -> None:
    bind = op.get_bind()
    indexes = {i["name"] for i in sa.inspect(bind).get_indexes("users")}
    if "ix_users_deleted_at" in indexes:
        op.drop_index("ix_users_deleted_at", table_name="users")
    columns = {c["name"] for c in sa.inspect(bind).get_columns("users")}
    if "deleted_at" in columns:
        op.drop_column("users", "deleted_at")
