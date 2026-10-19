"""Language publication: learn / native flags and the last readiness check

Existing enabled languages start published (nothing changes for people until
the first check); the background check then unpublishes any language that is
missing something, with the reason kept in last_check.

Revision ID: a6c8e0b2d4f7
Revises: f2b4d6a8c0e1
"""

import sqlalchemy as sa
from alembic import op

revision: str = "a6c8e0b2d4f7"
down_revision: str | None = "f2b4d6a8c0e1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("languages", sa.Column("learn_published", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column("languages", sa.Column("native_published", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column("languages", sa.Column("last_check", sa.JSON(), nullable=True))
    op.execute("UPDATE languages SET learn_published = is_enabled, native_published = is_enabled")


def downgrade() -> None:
    op.drop_column("languages", "last_check")
    op.drop_column("languages", "native_published")
    op.drop_column("languages", "learn_published")
