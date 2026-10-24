"""Diamonds come from the season pass only: switch the daily gift off.

Revision ID: c0d2e4f6a8b9
Revises: f8c1d2e3a4b5
"""
from alembic import op

revision = "c0d2e4f6a8b9"
down_revision = "f8c1d2e3a4b5"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("UPDATE gift_definitions SET enabled = false WHERE key = 'daily-chest'")
    op.execute("UPDATE pass_settings SET chest_enabled = false")
    op.execute("ALTER TABLE pass_settings ALTER COLUMN chest_enabled SET DEFAULT false")


def downgrade() -> None:
    op.execute("ALTER TABLE pass_settings ALTER COLUMN chest_enabled SET DEFAULT true")
    op.execute("UPDATE gift_definitions SET enabled = true WHERE key = 'daily-chest'")
    op.execute("UPDATE pass_settings SET chest_enabled = true")
