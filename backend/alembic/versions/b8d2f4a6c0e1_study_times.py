"""study times: user_study_times, follow-up delay, default study reminder texts

Revision ID: b8d2f4a6c0e1
Revises: a7c1e3f5b9d2
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "b8d2f4a6c0e1"
down_revision: Union[str, None] = "a7c1e3f5b9d2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "user_study_times",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("minute_of_day", sa.Integer(), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default="true"),
        sa.UniqueConstraint("user_id", "minute_of_day", name="uq_user_study_time"),
        sa.CheckConstraint("minute_of_day >= 0 AND minute_of_day < 1440", name="ck_user_study_time_minute"),
    )
    op.create_index("ix_user_study_times_user_id", "user_study_times", ["user_id"])
    op.add_column(
        "reminder_settings",
        sa.Column("study_followup_minutes", sa.Integer(), nullable=False, server_default="120"),
    )
    rules = sa.table(
        "reminder_rules",
        sa.column("kind", sa.String),
        sa.column("days", sa.Integer),
        sa.column("title", sa.String),
        sa.column("body", sa.Text),
        sa.column("enabled", sa.Boolean),
    )
    op.bulk_insert(
        rules,
        [
            {"kind": "study_time", "days": 1, "title": "Время заниматься 📚", "body": "5 минут — и слова не забудутся", "enabled": True},
            {"kind": "study_followup", "days": 1, "title": "Вы сегодня ещё не занимались", "body": "Загляните хотя бы на 5 минут — слова ждут вас", "enabled": True},
        ],
    )


def downgrade() -> None:
    op.execute("DELETE FROM reminder_rules WHERE kind IN ('study_time', 'study_followup')")
    op.drop_column("reminder_settings", "study_followup_minutes")
    op.drop_index("ix_user_study_times_user_id", table_name="user_study_times")
    op.drop_table("user_study_times")
