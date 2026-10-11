"""mini phrases

Revision ID: d832ce890768
Revises: 4eb1afc0a5c9
Create Date: 2026-10-11 09:45:17.729035

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd832ce890768'
down_revision: Union[str, None] = '4eb1afc0a5c9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("words", sa.Column("role", sa.String(length=32), nullable=True))

    op.create_table(
        "mini_phrase_templates",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(length=128), nullable=False),
        sa.Column("kind", sa.String(length=32), nullable=False, server_default="ordered_parts"),
        sa.Column("explanation_ru", sa.Text(), nullable=True),
        sa.Column("explanation_tg", sa.Text(), nullable=True),
        sa.Column("explanation_uz", sa.Text(), nullable=True),
        sa.Column("distractor_count", sa.Integer(), nullable=False, server_default="2"),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_table(
        "mini_phrases",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("dictionary_id", sa.Integer(), sa.ForeignKey("dictionaries.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("template_id", sa.Integer(), sa.ForeignKey("mini_phrase_templates.id", ondelete="SET NULL"), nullable=True, index=True),
        sa.Column("text", sa.String(length=500), nullable=False),
        sa.Column("translation_tg", sa.String(length=500), nullable=False),
        sa.Column("translation_uz", sa.String(length=500), nullable=True),
        sa.Column("translation_en", sa.String(length=500), nullable=True),
        sa.Column("audio_key", sa.Text(), nullable=True),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_table(
        "mini_phrase_parts",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("mini_phrase_id", sa.Integer(), sa.ForeignKey("mini_phrases.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("text", sa.String(length=255), nullable=False),
        sa.Column("word_id", sa.Integer(), sa.ForeignKey("words.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("word_form_id", sa.Integer(), sa.ForeignKey("word_forms.id", ondelete="SET NULL"), nullable=True),
        sa.Column("role", sa.String(length=32), nullable=True),
        sa.UniqueConstraint("mini_phrase_id", "position", name="uq_mini_phrase_part_position"),
    )
    op.create_table(
        "lesson_mini_phrases",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("lesson_id", sa.Integer(), sa.ForeignKey("lessons.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("mini_phrase_id", sa.Integer(), sa.ForeignKey("mini_phrases.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("position", sa.Integer(), nullable=False, server_default="0"),
        sa.UniqueConstraint("lesson_id", "mini_phrase_id", name="uq_lesson_mini_phrase"),
    )
    op.create_table(
        "user_mini_phrase_done",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("mini_phrase_id", sa.Integer(), sa.ForeignKey("mini_phrases.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("user_id", "mini_phrase_id", name="uq_user_mini_phrase_done"),
    )
    op.create_table(
        "user_mini_phrase_points",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("mini_phrase_id", sa.Integer(), sa.ForeignKey("mini_phrases.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("points_awarded", sa.Integer(), nullable=False),
        sa.Column("awarded_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("user_id", "mini_phrase_id", name="uq_user_mini_phrase_points"),
    )
    op.create_table(
        "mini_phrase_settings",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("points_enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("points_per_correct", sa.Integer(), nullable=False, server_default="5"),
        sa.Column("max_per_lesson", sa.Integer(), nullable=False, server_default="3"),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )


def downgrade() -> None:
    op.drop_table("mini_phrase_settings")
    op.drop_table("user_mini_phrase_points")
    op.drop_table("user_mini_phrase_done")
    op.drop_table("lesson_mini_phrases")
    op.drop_table("mini_phrase_parts")
    op.drop_table("mini_phrases")
    op.drop_table("mini_phrase_templates")
    op.drop_column("words", "role")
