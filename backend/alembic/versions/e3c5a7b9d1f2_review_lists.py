"""«Повторить сегодня» as fixed lists; answer context on word_attempts

Revision ID: e3c5a7b9d1f2
Revises: b5e8c2d6f0a3
"""

import sqlalchemy as sa
from alembic import op

revision: str = "e3c5a7b9d1f2"
down_revision: str | None = "b5e8c2d6f0a3"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "review_lists",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("dictionary_id", sa.Integer(), sa.ForeignKey("dictionaries.id", ondelete="CASCADE"), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("size", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("activated_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("closed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("notified_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_review_lists_user_id", "review_lists", ["user_id"])
    op.create_index("ix_review_lists_user_dict_status", "review_lists", ["user_id", "dictionary_id", "status"])
    op.create_table(
        "review_list_words",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("list_id", sa.Integer(), sa.ForeignKey("review_lists.id", ondelete="CASCADE"), nullable=False),
        sa.Column("word_id", sa.Integer(), sa.ForeignKey("words.id", ondelete="CASCADE"), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("recall", sa.Float(), nullable=False),
        sa.Column("target", sa.Float(), nullable=False),
        sa.Column("stability", sa.Float(), nullable=True),
        sa.Column("difficulty", sa.Float(), nullable=True),
        sa.Column("last_review", sa.DateTime(timezone=True), nullable=True),
        sa.Column("review_days", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("score", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("done_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_review_list_words_list_id", "review_list_words", ["list_id"])
    op.create_index("ix_review_list_words_word_id", "review_list_words", ["word_id"])
    op.add_column("word_attempts", sa.Column("phrase_id", sa.Integer(), sa.ForeignKey("phrases.id", ondelete="SET NULL"), nullable=True))
    op.add_column(
        "word_attempts",
        sa.Column("mini_phrase_id", sa.Integer(), sa.ForeignKey("mini_phrases.id", ondelete="SET NULL"), nullable=True),
    )
    op.add_column(
        "word_attempts",
        sa.Column("review_list_id", sa.Integer(), sa.ForeignKey("review_lists.id", ondelete="SET NULL"), nullable=True),
    )
    op.create_index("ix_word_attempts_review_list_id", "word_attempts", ["review_list_id"])


def downgrade() -> None:
    op.drop_index("ix_word_attempts_review_list_id", table_name="word_attempts")
    op.drop_column("word_attempts", "review_list_id")
    op.drop_column("word_attempts", "mini_phrase_id")
    op.drop_column("word_attempts", "phrase_id")
    op.drop_table("review_list_words")
    op.drop_table("review_lists")
