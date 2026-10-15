"""Reminder quiet hours become admin-editable

The «Повтори слово» push and the background preparation (auto lessons/quests)
were suppressed during a quiet window that was HARDCODED (23:00-08:00 Dushanbe).
These two columns make that window editable in Admin Web, with the same defaults.

Revision ID: d1b6a7e3c920
Revises: c8f4a9e2d715
Create Date: 2026-10-16

"""
from alembic import op
import sqlalchemy as sa

revision = "d1b6a7e3c920"
down_revision = "c8f4a9e2d715"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "reminder_settings",
        sa.Column("quiet_from_hour", sa.Integer(), nullable=False, server_default="23"),
    )
    op.add_column(
        "reminder_settings",
        sa.Column("quiet_to_hour", sa.Integer(), nullable=False, server_default="8"),
    )


def downgrade() -> None:
    op.drop_column("reminder_settings", "quiet_to_hour")
    op.drop_column("reminder_settings", "quiet_from_hour")
