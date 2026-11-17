"""Avatar built from parts (from the Avatar Studio) instead of an uploaded photo.

Old uploaded photos are cleared by decision of the owner: everyone sees the standard picture until they
build an avatar.

Revision ID: a1b2c3d4e5f6
Revises: d7e9f1a3b5c6
"""
import sqlalchemy as sa
from alembic import op

revision = "a1b2c3d4e5f6"
down_revision = "d7e9f1a3b5c6"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "avatar_items",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("slot", sa.String(32), nullable=False),
        sa.Column("gender", sa.String(8), nullable=False),
        sa.Column("name", sa.String(200), nullable=False, server_default=""),
        sa.Column("set_id", sa.String(64), nullable=False, server_default=""),
        sa.Column("set_name", sa.String(200), nullable=False, server_default=""),
        sa.Column("image_key", sa.String(500), nullable=False),
        sa.Column("image_hash", sa.String(40), nullable=False, server_default=""),
        sa.Column("width", sa.Integer, nullable=False, server_default="0"),
        sa.Column("height", sa.Integer, nullable=False, server_default="0"),
        sa.Column("place", sa.JSON, nullable=False),
        sa.Column("own_place", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column("active", sa.Boolean, nullable=False, server_default=sa.true()),
        sa.Column("version", sa.Integer, nullable=False, server_default="1"),
        sa.Column("sort", sa.Integer, nullable=False, server_default="0"),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_avatar_items_slot", "avatar_items", ["slot"])
    op.create_table(
        "avatar_backgrounds",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("name", sa.String(200), nullable=False, server_default=""),
        sa.Column("kind", sa.String(8), nullable=False),
        sa.Column("c1", sa.String(16), nullable=True),
        sa.Column("c2", sa.String(16), nullable=True),
        sa.Column("image_key", sa.String(500), nullable=True),
        sa.Column("image_hash", sa.String(40), nullable=False, server_default=""),
        sa.Column("width", sa.Integer, nullable=False, server_default="0"),
        sa.Column("height", sa.Integer, nullable=False, server_default="0"),
        sa.Column("place", sa.JSON, nullable=True),
        sa.Column("active", sa.Boolean, nullable=False, server_default=sa.true()),
        sa.Column("version", sa.Integer, nullable=False, server_default="1"),
        sa.Column("sort", sa.Integer, nullable=False, server_default="0"),
    )
    op.create_table(
        "avatar_meta",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("canvas", sa.JSON, nullable=False),
        sa.Column("frame", sa.JSON, nullable=True),
        sa.Column("slots", sa.JSON, nullable=False),
        sa.Column("version", sa.Integer, nullable=False, server_default="1"),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.add_column("users", sa.Column("avatar_look", sa.JSON, nullable=True))
    # No more uploaded photos: show the standard picture until the person builds an avatar.
    op.execute("UPDATE users SET avatar_key = NULL")


def downgrade() -> None:
    op.drop_column("users", "avatar_look")
    op.drop_table("avatar_meta")
    op.drop_table("avatar_backgrounds")
    op.drop_index("ix_avatar_items_slot", table_name="avatar_items")
    op.drop_table("avatar_items")
