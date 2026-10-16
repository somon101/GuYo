"""users.learning_language -- the language a person studies

Revision ID: 7c3b5e91a204
Revises: 2f7a1c4d9e05
Create Date: 2026-10-16 22:20:00.000000

Пара «родной -> изучаемый» определяет, что человек видит: ответ берётся из
языковой записи изучаемого языка, подсказка -- из записи родного. Родной уже
хранится (`translation_language`), изучаемого не было: он подразумевался языком
словаря. Колонка nullable -- пусто означает «язык словаря», поэтому поведение
существующих людей не меняется.

Написана вручную: автогенерация Alembic вместе с этим полем снова предлагает
ложные правки NOT NULL у чужих таблиц (см. 11d58d36beef).
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "7c3b5e91a204"
down_revision: Union[str, None] = "2f7a1c4d9e05"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("learning_language", sa.String(length=8), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "learning_language")
