"""Friend requests and requests to join a closed team.

Revision ID: b2c3d4e5f6a7
Revises: a1b2c3d4e5f6
"""
import sqlalchemy as sa
from alembic import op

revision = "b2c3d4e5f6a7"
down_revision = "a1b2c3d4e5f6"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "friend_requests",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("from_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("to_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("from_id", "to_id", name="uq_friend_request_pair"),
    )
    op.create_index("ix_friend_requests_from_id", "friend_requests", ["from_id"])
    op.create_index("ix_friend_requests_to_id", "friend_requests", ["to_id"])
    op.create_table(
        "team_join_requests",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("team_id", sa.Integer, sa.ForeignKey("teams.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("declined_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("team_id", "user_id", name="uq_team_join_request_once"),
    )
    op.create_index("ix_team_join_requests_team_id", "team_join_requests", ["team_id"])
    op.create_index("ix_team_join_requests_user_id", "team_join_requests", ["user_id"])


def downgrade() -> None:
    op.drop_table("team_join_requests")
    op.drop_table("friend_requests")
