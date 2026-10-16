"""mini-phrases get their own language

Revision ID: 2f7a1c4d9e05
Revises: 11d58d36beef
Create Date: 2026-10-16 21:30:00.000000

Мини-фраза собрана из языковых записей одного языка, поэтому должна знать, на
каком языке она написана: иначе после многоязычной перестройки непонятно, кому
её показывать. Колонка nullable -- значения проставляет перенос данных
(app/multilingual_backfill.py), а не миграция: язык берётся из словаря фразы.

Написана вручную: автогенерация Alembic вместе с этим полем снова предлагает
два десятка ложных правок NOT NULL у чужих таблиц (см. 11d58d36beef).
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "2f7a1c4d9e05"
down_revision: Union[str, None] = "11d58d36beef"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("mini_phrases", sa.Column("language", sa.String(length=8), nullable=True))
    op.create_index(op.f("ix_mini_phrases_language"), "mini_phrases", ["language"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_mini_phrases_language"), table_name="mini_phrases")
    op.drop_column("mini_phrases", "language")
