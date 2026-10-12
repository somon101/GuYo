"""quiet background preparation of auto lessons + «Повтори слово» push

Revision ID: b5e8c2d4f6a1
Revises: a4d7f1b5c9e2
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "b5e8c2d4f6a1"
down_revision: str | None = "a4d7f1b5c9e2"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("reminder_settings", sa.Column("prep_enabled", sa.Boolean(), nullable=False, server_default="true"))
    op.add_column("reminder_settings", sa.Column("prep_delay_minutes", sa.Integer(), nullable=False, server_default="20"))
    op.add_column("reminder_settings", sa.Column("review_push_min_words", sa.Integer(), nullable=False, server_default="10"))
    op.create_table(
        "user_prep_states",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("dictionary_id", sa.Integer(), sa.ForeignKey("dictionaries.id", ondelete="CASCADE"), nullable=False),
        sa.Column("last_activity_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("pending", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("review_notified_on", sa.Date(), nullable=True),
        sa.UniqueConstraint("user_id", "dictionary_id", name="uq_user_prep_state"),
    )
    op.create_index("ix_user_prep_states_user_id", "user_prep_states", ["user_id"])
    op.create_index("ix_user_prep_states_pending", "user_prep_states", ["pending"])


def downgrade() -> None:
    op.drop_index("ix_user_prep_states_pending", table_name="user_prep_states")
    op.drop_index("ix_user_prep_states_user_id", table_name="user_prep_states")
    op.drop_table("user_prep_states")
    op.drop_column("reminder_settings", "review_push_min_words")
    op.drop_column("reminder_settings", "prep_delay_minutes")
    op.drop_column("reminder_settings", "prep_enabled")
