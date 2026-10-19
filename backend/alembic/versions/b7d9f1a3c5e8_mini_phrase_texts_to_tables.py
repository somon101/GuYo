"""Copy mini-phrase hints and template explanations from the old fixed columns
into the per-language tables, which become the source of truth

Revision ID: b7d9f1a3c5e8
Revises: a6c8e0b2d4f7
"""

from alembic import op

revision: str = "b7d9f1a3c5e8"
down_revision: str | None = "a6c8e0b2d4f7"
branch_labels = None
depends_on = None


def upgrade() -> None:
    for code in ("tg", "uz", "en"):
        op.execute(
            f"""
            INSERT INTO mini_phrase_translations (mini_phrase_id, language, text)
            SELECT mp.id, '{code}', mp.translation_{code}
            FROM mini_phrases mp
            WHERE mp.translation_{code} IS NOT NULL AND btrim(mp.translation_{code}) <> ''
              AND NOT EXISTS (
                SELECT 1 FROM mini_phrase_translations t
                WHERE t.mini_phrase_id = mp.id AND t.language = '{code}'
              )
            """
        )
    for code in ("ru", "tg", "uz"):
        op.execute(
            f"""
            INSERT INTO mini_phrase_template_translations (template_id, language, text)
            SELECT t.id, '{code}', t.explanation_{code}
            FROM mini_phrase_templates t
            WHERE t.explanation_{code} IS NOT NULL AND btrim(t.explanation_{code}) <> ''
              AND NOT EXISTS (
                SELECT 1 FROM mini_phrase_template_translations x
                WHERE x.template_id = t.id AND x.language = '{code}'
              )
            """
        )


def downgrade() -> None:
    pass
