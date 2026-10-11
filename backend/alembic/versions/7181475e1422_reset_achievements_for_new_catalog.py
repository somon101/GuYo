"""reset achievements for new catalog

Revision ID: 7181475e1422
Revises: f6a0b2c4d5e7
Create Date: 2026-10-11 05:31:24.243989

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7181475e1422'
down_revision: Union[str, None] = 'f6a0b2c4d5e7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # One-time wipe of the old hand-made achievements so the fresh,
    # structured catalog seeded by app/seed.py (which runs right after
    # `alembic upgrade head` in the Procfile) becomes the only set.
    # This runs exactly once; a later deploy skips an already-applied
    # revision, so the admin's own additions are never wiped again.
    #
    # Deleting an achievement also removes every user's grant for it
    # (user_achievements.achievement_id is ON DELETE CASCADE), so this is
    # irreversible: users who earned an old badge lose it. We delete the
    # grants explicitly first anyway, so this works even if the cascade is
    # ever changed.
    op.execute("DELETE FROM user_achievements")
    op.execute("DELETE FROM achievements")


def downgrade() -> None:
    # The deleted definitions and grants cannot be reconstructed; the
    # new catalog is (re)created by app/seed.py, not by a downgrade.
    pass
