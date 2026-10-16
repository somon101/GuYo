"""users.learning_language -- already exists; this revision only records it

Revision ID: 7c3b5e91a204
Revises: 2f7a1c4d9e05
Create Date: 2026-10-16 22:20:00.000000

ВНИМАНИЕ. Колонка `users.learning_language` существовала ЗАДОЛГО до этой
ревизии: это язык, который человек выбрал при регистрации (app/models/user.py,
Dictionary.language codes). Первая версия этой миграции пыталась её добавить --
и на боевой базе это уронило деплой: `DuplicateColumn`, а так как в Procfile
`alembic upgrade head` идёт ДО запуска приложения, сервис не поднялся вовсе.

Теперь миграция ИДЕМПОТЕНТНА: колонку добавляет, только если её нет. Downgrade
ничего не удаляет -- колонка не наша, в ней данные людей.
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
    columns = {column["name"] for column in sa.inspect(op.get_bind()).get_columns("users")}
    if "learning_language" not in columns:
        op.add_column("users", sa.Column("learning_language", sa.String(length=16), nullable=True))


def downgrade() -> None:
    # Намеренно пусто: колонка принадлежала таблице до этой ревизии, и удалять
    # её (вместе с ответами людей) нельзя.
    pass
