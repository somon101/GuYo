"""season periods, scheduling statuses and icon

Gives every season a real period with a time of day instead of two plain
dates, plus the picture an admin uploads for it.

`start_date`/`end_date` carried two different meanings in one pair of
columns: when the season began, and when it happened to be ended. They
become three explicit ones:

  start_date -> starts_at   when the season begins (planned or actual)
                ends_at     the PLANNED end, null = "only an admin ends it"
  end_date   -> ended_at    when it ACTUALLY ended, null until then

Existing rows keep their meaning exactly: an old start_date becomes
midnight UTC of that day, an old end_date becomes the recorded ended_at
(a completed season already had one, a running season had null), and
ends_at starts out null -- i.e. every season that exists today keeps
behaving as "ends when an admin says so", which is what it did before.

The partial unique index is the database-level half of "at most one
active season", the same idiom lessons already use for "at most one
incomplete lesson per user/dictionary".

Revision ID: d2c4a7f1e903
Revises: b71c93af2d10
Create Date: 2026-09-24 06:10:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd2c4a7f1e903'
down_revision: Union[str, None] = 'b71c93af2d10'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.alter_column(
        'seasons',
        'start_date',
        new_column_name='starts_at',
        type_=sa.DateTime(timezone=True),
        existing_type=sa.Date(),
        existing_nullable=False,
        postgresql_using="start_date::timestamptz",
    )
    op.alter_column(
        'seasons',
        'end_date',
        new_column_name='ended_at',
        type_=sa.DateTime(timezone=True),
        existing_type=sa.Date(),
        existing_nullable=True,
        postgresql_using="end_date::timestamptz",
    )
    op.add_column('seasons', sa.Column('ends_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('seasons', sa.Column('icon_key', sa.String(length=500), nullable=True))
    op.alter_column('seasons', 'status', server_default='scheduled', existing_type=sa.String(length=16))
    op.create_index(
        'uq_single_active_season',
        'seasons',
        ['status'],
        unique=True,
        postgresql_where=sa.text("status = 'active'"),
    )


def downgrade() -> None:
    op.drop_index('uq_single_active_season', table_name='seasons')
    op.alter_column('seasons', 'status', server_default='active', existing_type=sa.String(length=16))
    op.drop_column('seasons', 'icon_key')
    op.drop_column('seasons', 'ends_at')
    op.alter_column(
        'seasons',
        'ended_at',
        new_column_name='end_date',
        type_=sa.Date(),
        existing_type=sa.DateTime(timezone=True),
        existing_nullable=True,
        postgresql_using="ended_at::date",
    )
    op.alter_column(
        'seasons',
        'starts_at',
        new_column_name='start_date',
        type_=sa.Date(),
        existing_type=sa.DateTime(timezone=True),
        existing_nullable=False,
        postgresql_using="starts_at::date",
    )
