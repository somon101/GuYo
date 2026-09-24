"""add quest daily target

How many successful attempts count as "this quest is done for today" --
the goal a user's progress bar fills toward. Existing quests default to 1,
i.e. exactly the behaviour they had before: one successful attempt and the
quest reads as done.

Deliberately NOT a reward rule: every successful attempt still grants the
quest's reward_points, target reached or not, and progress is counted from
the user_quest_word_days rows that already exist rather than stored here.

Revision ID: e5f1b9c73d20
Revises: d2c4a7f1e903
Create Date: 2026-09-24 07:20:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e5f1b9c73d20'
down_revision: Union[str, None] = 'd2c4a7f1e903'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'quests',
        sa.Column('daily_target', sa.Integer(), nullable=False, server_default='1'),
    )
    op.create_check_constraint('ck_quest_daily_target_positive', 'quests', 'daily_target >= 1')


def downgrade() -> None:
    op.drop_constraint('ck_quest_daily_target_positive', 'quests', type_='check')
    op.drop_column('quests', 'daily_target')
