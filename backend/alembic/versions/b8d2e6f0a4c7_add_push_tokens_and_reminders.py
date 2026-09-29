"""add push tokens and reminders

  push_tokens        one FCM registration token per phone
  reminder_rules     admin-editable automatic messages (inactivity,
                     streak at risk, streak milestones), seeded with the
                     texts agreed with the owner
  reminder_settings  single row: when the streak warning goes out, and the
                     fallback hour for inactivity reminders

Revision ID: b8d2e6f0a4c7
Revises: a2c8e4f6b1d3
Create Date: 2026-09-29 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b8d2e6f0a4c7'
down_revision: Union[str, None] = 'a2c8e4f6b1d3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


SEED_RULES = [
    ("inactivity", 1, "GuYo", "Не забудь про занятие — 5 минут сегодня"),
    ("inactivity", 3, "GuYo", "Слова забываются без повторения. Вернись!"),
    ("inactivity", 7, "GuYo", "Мы скучаем! Твой прогресс ждёт тебя"),
    ("streak_risk", 2, "Серия дней", "🔥 Твоя серия — {дни} дн. Зайди сегодня, чтобы не потерять её!"),
    ("streak_risk", 2, "Серия дней", "Не прерывай серию! Всего 5 минут — и {дни} дн. подряд станут {дни+1}"),
    ("streak_milestone", 7, "Поздравляем!", "🎉 7 дней подряд! Так держать!"),
    ("streak_milestone", 30, "Поздравляем!", "🏆 30 дней подряд! Ты молодец!"),
    ("streak_milestone", 100, "Поздравляем!", "💯 100 дней подряд! Это настоящий рекорд!"),
]


def upgrade() -> None:
    op.create_table(
        'push_tokens',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('token', sa.String(length=512), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('token'),
    )
    op.create_index('ix_push_tokens_user_id', 'push_tokens', ['user_id'])

    rules = op.create_table(
        'reminder_rules',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('kind', sa.String(length=32), nullable=False),
        sa.Column('days', sa.Integer(), nullable=False),
        sa.Column('title', sa.String(length=120), nullable=True),
        sa.Column('body', sa.Text(), nullable=False),
        sa.Column('enabled', sa.Boolean(), server_default='true', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.CheckConstraint('days >= 1', name='ck_reminder_rule_days_positive'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_reminder_rules_kind', 'reminder_rules', ['kind'])
    op.bulk_insert(rules, [{"kind": k, "days": d, "title": t, "body": b} for k, d, t, b in SEED_RULES])

    op.create_table(
        'reminder_settings',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('streak_risk_hour', sa.Integer(), server_default='20', nullable=False),
        sa.Column('default_hour', sa.Integer(), server_default='18', nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.PrimaryKeyConstraint('id'),
    )
    op.execute("INSERT INTO reminder_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING")


def downgrade() -> None:
    op.drop_table('reminder_settings')
    op.drop_index('ix_reminder_rules_kind', table_name='reminder_rules')
    op.drop_table('reminder_rules')
    op.drop_index('ix_push_tokens_user_id', table_name='push_tokens')
    op.drop_table('push_tokens')
