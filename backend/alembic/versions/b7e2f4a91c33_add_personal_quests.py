"""add personal auto-quests

Revision ID: b7e2f4a91c33
Revises: 3c0cdf54b6a2
Create Date: 2026-09-25 20:10:00.000000

A personal quest reuses the existing `quests` table (see
app/models/quest.py's own docstring): `owner_user_id` set marks a row as
personal instead of admin-authored, and `word_level_id` becomes nullable
because a personal quest's words come from Priority (High/Medium role),
not a single level range -- its fixed word set lives in the new
`quest_words` table instead (same role LessonWord plays for Lesson).

The 5 new `priority_settings` columns are, same discipline as the rest of
Priority, starting examples an admin can retune from the moment this
lands -- not business math anyone has signed off on.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b7e2f4a91c33'
down_revision: Union[str, None] = '3c0cdf54b6a2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.alter_column('quests', 'word_level_id', existing_type=sa.Integer(), nullable=True)
    op.add_column('quests', sa.Column('owner_user_id', sa.Integer(), nullable=True))
    op.create_index(op.f('ix_quests_owner_user_id'), 'quests', ['owner_user_id'], unique=False)
    op.create_foreign_key(
        'fk_quests_owner_user_id_users', 'quests', 'users', ['owner_user_id'], ['id'], ondelete='CASCADE'
    )

    op.create_table(
        'quest_words',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('quest_id', sa.Integer(), nullable=False),
        sa.Column('word_id', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['quest_id'], ['quests.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['word_id'], ['words.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('quest_id', 'word_id', name='uq_quest_word'),
    )
    op.create_index(op.f('ix_quest_words_quest_id'), 'quest_words', ['quest_id'], unique=False)

    op.add_column('priority_settings', sa.Column('personal_quest_min_attempts', sa.Integer(), server_default='2', nullable=False))
    op.add_column('priority_settings', sa.Column('personal_quest_weak_error_rate', sa.Float(), server_default='0.5', nullable=False))
    op.add_column('priority_settings', sa.Column('personal_quest_min_words', sa.Integer(), server_default='3', nullable=False))
    op.add_column('priority_settings', sa.Column('personal_quest_max_words', sa.Integer(), server_default='5', nullable=False))
    op.add_column('priority_settings', sa.Column('personal_quest_reward_points', sa.Integer(), server_default='10', nullable=False))


def downgrade() -> None:
    op.drop_column('priority_settings', 'personal_quest_reward_points')
    op.drop_column('priority_settings', 'personal_quest_max_words')
    op.drop_column('priority_settings', 'personal_quest_min_words')
    op.drop_column('priority_settings', 'personal_quest_weak_error_rate')
    op.drop_column('priority_settings', 'personal_quest_min_attempts')

    op.drop_index(op.f('ix_quest_words_quest_id'), table_name='quest_words')
    op.drop_table('quest_words')

    op.drop_constraint('fk_quests_owner_user_id_users', 'quests', type_='foreignkey')
    op.drop_index(op.f('ix_quests_owner_user_id'), table_name='quests')
    op.drop_column('quests', 'owner_user_id')
    op.alter_column('quests', 'word_level_id', existing_type=sa.Integer(), nullable=False)
