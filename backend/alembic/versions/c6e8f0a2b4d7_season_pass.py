"""Season pass: XP settings, templates, a season's own copy, XP events, claims.

Revision ID: c6e8f0a2b4d7
Revises: b5d7f9a1c3e6
"""

import sqlalchemy as sa
from alembic import op

revision: str = "c6e8f0a2b4d7"
down_revision: str | None = "b5d7f9a1c3e6"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "pass_settings",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("xp_word", sa.Integer(), server_default="10", nullable=False),
        sa.Column("xp_lesson", sa.Integer(), server_default="20", nullable=False),
        sa.Column("xp_review", sa.Integer(), server_default="2", nullable=False),
        sa.Column("xp_quest", sa.Integer(), server_default="15", nullable=False),
        sa.Column("xp_streak", sa.Integer(), server_default="10", nullable=False),
        sa.Column("auto_monthly_seasons", sa.Boolean(), server_default="true", nullable=False),
    )
    op.create_table(
        "pass_templates",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("is_default", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("definition", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_table(
        "season_passes",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("season_id", sa.Integer(), sa.ForeignKey("seasons.id", ondelete="CASCADE"), nullable=False),
        sa.Column("template_id", sa.Integer(), sa.ForeignKey("pass_templates.id", ondelete="SET NULL"), nullable=True),
        sa.Column("definition", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_season_passes_season_id", "season_passes", ["season_id"], unique=True)
    op.create_table(
        "pass_xp_events",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("season_id", sa.Integer(), sa.ForeignKey("seasons.id", ondelete="CASCADE"), nullable=False),
        sa.Column("source", sa.String(length=16), nullable=False),
        sa.Column("amount", sa.Integer(), nullable=False),
        sa.Column("dedupe_key", sa.String(length=120), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("user_id", "season_id", "dedupe_key", name="uq_pass_xp_once"),
    )
    op.create_index("ix_pass_xp_events_user_id", "pass_xp_events", ["user_id"])
    op.create_index("ix_pass_xp_events_season_id", "pass_xp_events", ["season_id"])
    op.create_index("ix_pass_xp_events_created_at", "pass_xp_events", ["created_at"])
    op.create_table(
        "pass_claims",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("season_id", sa.Integer(), sa.ForeignKey("seasons.id", ondelete="CASCADE"), nullable=False),
        sa.Column("kind", sa.String(length=8), nullable=False),
        sa.Column("ref", sa.String(length=64), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("user_id", "season_id", "kind", "ref", name="uq_pass_claim_once"),
    )
    op.create_index("ix_pass_claims_user_id", "pass_claims", ["user_id"])
    op.create_index("ix_pass_claims_season_id", "pass_claims", ["season_id"])


def downgrade() -> None:
    op.drop_table("pass_claims")
    op.drop_table("pass_xp_events")
    op.drop_table("season_passes")
    op.drop_table("pass_templates")
    op.drop_table("pass_settings")
