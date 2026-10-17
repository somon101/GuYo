"""Шаблон мини-фразы принадлежит языку, объяснения — в таблицу переводов

Шаблон описывает ПОРЯДОК частей фразы, а порядок — свойство языка. Пока все
фразы русские, шаблон был «общий», и его объяснение лежало в трёх колонках
(explanation_ru/tg/uz). Для фразы на другом языке это неверно: и порядок, и
текст объяснения должны быть на её языке.

Что делает миграция:
1. mini_phrase_templates.language — у существующих шаблонов 'ru'.
2. mini_phrase_template_translations — по строке на язык, как у переводов
   мини-фраз. Старые три колонки остаются и копируются сюда, поэтому чтение не
   ломается.

Revision ID: f1a9c3e57b28
Revises: e6b3d8a24f17
"""

from alembic import op
import sqlalchemy as sa

revision = "f1a9c3e57b28"
down_revision = "e6b3d8a24f17"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    tables = set(sa.inspect(bind).get_table_names())

    columns = {c["name"] for c in sa.inspect(bind).get_columns("mini_phrase_templates")}
    if "language" not in columns:
        op.add_column(
            "mini_phrase_templates", sa.Column("language", sa.String(length=8), nullable=True)
        )
    # Существующие шаблоны описывают русские фразы.
    op.execute("update mini_phrase_templates set language = 'ru' where language is null")

    if "mini_phrase_template_translations" not in tables:
        op.create_table(
            "mini_phrase_template_translations",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "template_id",
                sa.Integer(),
                sa.ForeignKey("mini_phrase_templates.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("language", sa.String(length=8), nullable=False),
            sa.Column("text", sa.Text(), nullable=False),
            sa.UniqueConstraint(
                "template_id", "language", name="uq_mini_phrase_template_translations"
            ),
        )
        op.create_index(
            "ix_mini_phrase_template_translations_template_id",
            "mini_phrase_template_translations",
            ["template_id"],
        )
        op.create_index(
            "ix_mini_phrase_template_translations_language",
            "mini_phrase_template_translations",
            ["language"],
        )

    for code, column in (("ru", "explanation_ru"), ("tg", "explanation_tg"), ("uz", "explanation_uz")):
        op.execute(
            f"""
            insert into mini_phrase_template_translations (template_id, language, text)
            select id, '{code}', {column} from mini_phrase_templates
            where coalesce({column}, '') <> ''
            on conflict (template_id, language) do nothing
            """
        )


def downgrade() -> None:
    op.drop_table("mini_phrase_template_translations")
    bind = op.get_bind()
    columns = {c["name"] for c in sa.inspect(bind).get_columns("mini_phrase_templates")}
    if "language" in columns:
        op.drop_column("mini_phrase_templates", "language")
