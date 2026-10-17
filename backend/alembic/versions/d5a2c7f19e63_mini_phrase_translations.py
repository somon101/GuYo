"""Переводы мини-фраз на любой язык: таблица mini_phrase_translations

Раньше у мини-фразы были ровно три колонки перевода — tg, uz, en. Четвёртый
язык нельзя было ни сгенерировать, ни сохранить: добавили в админке немецкий,
а генератор про него просто не спрашивал. Теперь переводов столько, сколько
языков в таблице languages.

Старые колонки остаются и продолжают заполняться: их читает API для тех трёх
языков, и ломать это ради красоты незачем.

Revision ID: d5a2c7f19e63
Revises: c4f8a1b6d920
"""

from alembic import op
import sqlalchemy as sa

revision = "d5a2c7f19e63"
down_revision = "c4f8a1b6d920"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    tables = set(sa.inspect(bind).get_table_names())
    if "mini_phrase_translations" not in tables:
        op.create_table(
            "mini_phrase_translations",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "mini_phrase_id",
                sa.Integer(),
                sa.ForeignKey("mini_phrases.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("language", sa.String(length=8), nullable=False),
            sa.Column("text", sa.String(length=1000), nullable=False),
            sa.UniqueConstraint("mini_phrase_id", "language", name="uq_mini_phrase_translations"),
        )
        op.create_index(
            "ix_mini_phrase_translations_mini_phrase_id",
            "mini_phrase_translations",
            ["mini_phrase_id"],
        )
        op.create_index(
            "ix_mini_phrase_translations_language", "mini_phrase_translations", ["language"]
        )

    # Переносим уже существующие переводы, чтобы чтение не сломалось.
    op.execute(
        """
        insert into mini_phrase_translations (mini_phrase_id, language, text)
        select id, 'tg', translation_tg from mini_phrases
        where coalesce(translation_tg, '') <> ''
        on conflict (mini_phrase_id, language) do nothing
        """
    )
    op.execute(
        """
        insert into mini_phrase_translations (mini_phrase_id, language, text)
        select id, 'uz', translation_uz from mini_phrases
        where coalesce(translation_uz, '') <> ''
        on conflict (mini_phrase_id, language) do nothing
        """
    )
    op.execute(
        """
        insert into mini_phrase_translations (mini_phrase_id, language, text)
        select id, 'en', translation_en from mini_phrases
        where coalesce(translation_en, '') <> ''
        on conflict (mini_phrase_id, language) do nothing
        """
    )


def downgrade() -> None:
    op.drop_table("mini_phrase_translations")
