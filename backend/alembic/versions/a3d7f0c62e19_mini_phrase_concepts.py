"""Мини-фразы становятся «понятие + записи по языкам»

Сейчас строка mini_phrases — это фраза ОДНОГО языка: текст, язык и переводы в
трёх колонках. Из-за этого фраза на втором языке — отдельная запись, никак не
связанная с первой, а части фразы всегда ссылаются на слова одного словаря.

Вводим понятие мини-фразы: смысл, общий для языков. Каждая языковая запись —
это mini_phrases с concept_id: свой текст, свои части, свой шаблон, потому что
порядок слов и грамматика у языков разные.

Эта миграция ничего не меняет в поведении: у каждой существующей фразы
появляется своё понятие (связь один-к-одному). Дальше записи разных языков
можно будет привязывать к одному понятию.

Revision ID: a3d7f0c62e19
Revises: f1a9c3e57b28
"""

from alembic import op
import sqlalchemy as sa

revision = "a3d7f0c62e19"
down_revision = "f1a9c3e57b28"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    tables = set(sa.inspect(bind).get_table_names())

    if "mini_phrase_concepts" not in tables:
        op.create_table(
            "mini_phrase_concepts",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "dictionary_id",
                sa.Integer(),
                sa.ForeignKey("dictionaries.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        )
        op.create_index(
            "ix_mini_phrase_concepts_dictionary_id", "mini_phrase_concepts", ["dictionary_id"]
        )

    columns = {c["name"] for c in sa.inspect(bind).get_columns("mini_phrases")}
    if "concept_id" not in columns:
        op.add_column("mini_phrases", sa.Column("concept_id", sa.Integer(), nullable=True))
        op.create_index("ix_mini_phrases_concept_id", "mini_phrases", ["concept_id"])

    # Каждой существующей фразе — своё понятие (пока один-к-одному).
    rows = bind.execute(
        sa.text(
            "select id, dictionary_id from mini_phrases where concept_id is null order by id"
        )
    ).fetchall()
    for mp_id, dictionary_id in rows:
        concept_id = bind.execute(
            sa.text(
                "insert into mini_phrase_concepts (dictionary_id) values (:d) returning id"
            ),
            {"d": dictionary_id},
        ).scalar()
        bind.execute(
            sa.text("update mini_phrases set concept_id = :c where id = :m"),
            {"c": concept_id, "m": mp_id},
        )


def downgrade() -> None:
    bind = op.get_bind()
    columns = {c["name"] for c in sa.inspect(bind).get_columns("mini_phrases")}
    if "concept_id" in columns:
        op.drop_index("ix_mini_phrases_concept_id", table_name="mini_phrases")
        op.drop_column("mini_phrases", "concept_id")
    if "mini_phrase_concepts" in set(sa.inspect(bind).get_table_names()):
        op.drop_table("mini_phrase_concepts")
