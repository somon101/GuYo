"""add user public_id, names and email

Gives every account the 9-digit number the profile shows, plus the three
personal fields new accounts now require.

Deliberately additive: the primary key and every foreign key pointing at
it are untouched, so no relationship is rewritten and no issued auth token
stops working. Existing accounts keep their internal id and simply gain a
public_id.

public_id is filled in three steps -- add nullable, backfill, then enforce
-- because it has to be NOT NULL and UNIQUE in the end but cannot be
either while existing rows are still empty. The backfill draws a random
9-digit number per row and retries on collision, which is the same rule
new accounts use at runtime (app/core/public_id.py).

first_name/last_name/email stay nullable: accounts created before they
existed do not have them, and forcing a value would mean inventing one.
They are required of NEW accounts by the API schema instead. email is
unique where present -- Postgres allows any number of NULLs under a unique
constraint, so older accounts are unaffected.

Revision ID: f7a3d19c0b42
Revises: e5f1b9c73d20
Create Date: 2026-09-24 22:10:00.000000

"""
import random
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'f7a3d19c0b42'
down_revision: Union[str, None] = 'e5f1b9c73d20'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

PUBLIC_ID_MIN = 100_000_000
PUBLIC_ID_MAX = 999_999_999


def upgrade() -> None:
    op.add_column('users', sa.Column('public_id', sa.Integer(), nullable=True))
    op.add_column('users', sa.Column('first_name', sa.String(length=100), nullable=True))
    op.add_column('users', sa.Column('last_name', sa.String(length=100), nullable=True))
    op.add_column('users', sa.Column('email', sa.String(length=255), nullable=True))

    connection = op.get_bind()
    user_ids = [row[0] for row in connection.execute(sa.text('SELECT id FROM users ORDER BY id'))]
    taken: set[int] = set()
    for user_id in user_ids:
        while True:
            candidate = random.randint(PUBLIC_ID_MIN, PUBLIC_ID_MAX)
            if candidate not in taken:
                taken.add(candidate)
                break
        connection.execute(
            sa.text('UPDATE users SET public_id = :public_id WHERE id = :id'),
            {'public_id': candidate, 'id': user_id},
        )

    op.alter_column('users', 'public_id', existing_type=sa.Integer(), nullable=False)
    op.create_index('ix_users_public_id', 'users', ['public_id'], unique=True)
    op.create_index('ix_users_email', 'users', ['email'], unique=True)


def downgrade() -> None:
    op.drop_index('ix_users_email', table_name='users')
    op.drop_index('ix_users_public_id', table_name='users')
    op.drop_column('users', 'email')
    op.drop_column('users', 'last_name')
    op.drop_column('users', 'first_name')
    op.drop_column('users', 'public_id')
