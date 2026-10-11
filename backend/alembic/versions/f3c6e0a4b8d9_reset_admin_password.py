"""one-time admin password reset (the owner forgot it)

Only the bcrypt hash of a random 20-character password is stored here; the
password itself was given to the owner directly and should be changed in
Admin Web right away.

Revision ID: f3c6e0a4b8d9
Revises: d832ce890768
Create Date: 2026-10-11 18:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "f3c6e0a4b8d9"
down_revision: Union[str, None] = "d832ce890768"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

PASSWORD_HASH = "$2b$12$Q6lbD6V2O9VRy8wZff9OauoXYwCJhMxCiPZFeZbUGfe6s2LATnX9i"


def upgrade() -> None:
    op.get_bind().execute(
        sa.text("UPDATE admins SET password_hash = :h WHERE login = 'admin'"), {"h": PASSWORD_HASH}
    )


def downgrade() -> None:
    pass
