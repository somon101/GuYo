"""Daily-goal rewards are claimed by hand; notifications can carry a button.

Revision ID: f3a5b7c9d1e2
Revises: e2f4a6b8c0d1
"""
import sqlalchemy as sa
from alembic import op

revision = "f3a5b7c9d1e2"
down_revision = "e2f4a6b8c0d1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("daily_goal_claims", sa.Column("claimed_at", sa.DateTime(timezone=True)))
    op.add_column("daily_goal_claims", sa.Column("notified", sa.Boolean, nullable=False, server_default="false"))
    # Rewards already paid under the old rule count as taken.
    op.execute("UPDATE daily_goal_claims SET claimed_at = day::timestamp, notified = true")
    op.add_column("notifications", sa.Column("action", sa.String(64)))
    op.add_column("notifications", sa.Column("payload", sa.JSON))


def downgrade() -> None:
    op.drop_column("notifications", "payload")
    op.drop_column("notifications", "action")
    op.drop_column("daily_goal_claims", "notified")
    op.drop_column("daily_goal_claims", "claimed_at")
