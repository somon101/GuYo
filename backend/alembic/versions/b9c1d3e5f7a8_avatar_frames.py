"""users.equipped_frame_id (avatar frames from the season pass)

Revision ID: b9c1d3e5f7a8
Revises: a8b0c2d4e6f7
"""
import sqlalchemy as sa
from alembic import op

revision = "b9c1d3e5f7a8"
down_revision = "a8b0c2d4e6f7"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("equipped_frame_id", sa.Integer(), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "equipped_frame_id")
