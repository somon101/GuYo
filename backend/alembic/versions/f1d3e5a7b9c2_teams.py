"""Teams: the team, its members and invitations, and the team size setting.

Revision ID: f1d3e5a7b9c2
Revises: e9b1c3d5f7a0
"""

import sqlalchemy as sa
from alembic import op

revision: str = "f1d3e5a7b9c2"
down_revision: str | None = "e9b1c3d5f7a0"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("pass_settings", sa.Column("team_size", sa.Integer(), server_default="5", nullable=False))
    op.create_table(
        "teams",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(length=48), nullable=False),
        sa.Column("owner_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("is_open", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_table(
        "team_members",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("team_id", sa.Integer(), sa.ForeignKey("teams.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("joined_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_team_members_team_id", "team_members", ["team_id"])
    op.create_index("ix_team_members_user_id", "team_members", ["user_id"], unique=True)
    op.create_table(
        "team_invites",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("team_id", sa.Integer(), sa.ForeignKey("teams.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("invited_by", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("team_id", "user_id", name="uq_team_invite_once"),
    )
    op.create_index("ix_team_invites_team_id", "team_invites", ["team_id"])
    op.create_index("ix_team_invites_user_id", "team_invites", ["user_id"])


def downgrade() -> None:
    op.drop_table("team_invites")
    op.drop_table("team_members")
    op.drop_table("teams")
    op.drop_column("pass_settings", "team_size")
