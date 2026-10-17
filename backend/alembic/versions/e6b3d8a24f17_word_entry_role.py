"""Роль (часть речи) переезжает на языковую запись: word_entries.role

Роль — свойство языка, а не понятия: одно и то же понятие может быть глаголом в
одном языке и существительным в другом, а в языках без предлогов самой роли
«предлог» нет. Раньше роль лежала только на понятии (words.role), одна на все
языки, и шаблоны мини-фраз строились по ней для всех.

Теперь роль есть у каждой языковой записи. Значение с понятия остаётся
ЗАПАСНЫМ: у существующих записей оно копируется, чтобы ничего не изменилось, и
любой новый язык начинает с него.

Revision ID: e6b3d8a24f17
Revises: d5a2c7f19e63
"""

from alembic import op
import sqlalchemy as sa

revision = "e6b3d8a24f17"
down_revision = "d5a2c7f19e63"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    columns = {c["name"] for c in sa.inspect(bind).get_columns("word_entries")}
    if "role" not in columns:
        op.add_column("word_entries", sa.Column("role", sa.String(length=32), nullable=True))

    # Копируем роль понятия в каждую его языковую запись: поведение для уже
    # наполненных языков не меняется, а дальше роль правится по языку.
    op.execute(
        """
        update word_entries e
        set role = w.role
        from words w
        where w.id = e.concept_id
          and e.role is null
          and w.role is not null
        """
    )


def downgrade() -> None:
    bind = op.get_bind()
    columns = {c["name"] for c in sa.inspect(bind).get_columns("word_entries")}
    if "role" in columns:
        op.drop_column("word_entries", "role")
