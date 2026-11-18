"""The feed: cards, likes, ready-made comments, views; and «show me only to friends».

Revision ID: c3d4e5f6a7b8
Revises: b2c3d4e5f6a7
"""
import sqlalchemy as sa
from alembic import op

revision = "c3d4e5f6a7b8"
down_revision = "b2c3d4e5f6a7"
branch_labels = None
depends_on = None


def _user_fk(name: str = "user_id"):
    return sa.Column(name, sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False)


def _card_fk():
    return sa.Column("card_id", sa.Integer, sa.ForeignKey("feed_cards.id", ondelete="CASCADE"), nullable=False)


def upgrade() -> None:
    op.create_table(
        "feed_cards",
        sa.Column("id", sa.Integer, primary_key=True),
        _user_fk(),
        sa.Column("kind", sa.String(16), nullable=False),
        sa.Column("data", sa.JSON, nullable=False),
        sa.Column("dedupe_key", sa.String(120), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("views", sa.Integer, nullable=False, server_default="0"),
        sa.Column("reach", sa.Integer, nullable=False, server_default="30"),
        sa.Column("likes", sa.Integer, nullable=False, server_default="0"),
        sa.Column("comments", sa.Integer, nullable=False, server_default="0"),
        sa.UniqueConstraint("dedupe_key", name="uq_feed_card_once"),
    )
    op.create_index("ix_feed_cards_user_id", "feed_cards", ["user_id"])
    op.create_index("ix_feed_cards_created", "feed_cards", ["created_at"])
    op.create_table(
        "feed_likes",
        sa.Column("id", sa.Integer, primary_key=True),
        _card_fk(),
        _user_fk(),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("card_id", "user_id", name="uq_feed_like_once"),
    )
    op.create_index("ix_feed_likes_card_id", "feed_likes", ["card_id"])
    op.create_index("ix_feed_likes_user_id", "feed_likes", ["user_id"])
    op.create_table(
        "feed_comments",
        sa.Column("id", sa.Integer, primary_key=True),
        _card_fk(),
        _user_fk(),
        sa.Column("phrase", sa.String(64), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("card_id", "user_id", name="uq_feed_comment_once"),
    )
    op.create_index("ix_feed_comments_card_id", "feed_comments", ["card_id"])
    op.create_index("ix_feed_comments_user_id", "feed_comments", ["user_id"])
    op.create_table(
        "feed_seen",
        sa.Column("id", sa.Integer, primary_key=True),
        _card_fk(),
        _user_fk(),
        sa.Column("hidden", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.UniqueConstraint("card_id", "user_id", name="uq_feed_seen_once"),
    )
    op.create_index("ix_feed_seen_card_id", "feed_seen", ["card_id"])
    op.create_index("ix_feed_seen_user_id", "feed_seen", ["user_id"])
    op.add_column("users", sa.Column("feed_friends_only", sa.Boolean, nullable=False, server_default=sa.false()))


def downgrade() -> None:
    op.drop_column("users", "feed_friends_only")
    for t in ("feed_seen", "feed_comments", "feed_likes", "feed_cards"):
        op.drop_table(t)
