"""real action achievements: phrase opens + lesson completed_by_pass

Revision ID: 4eb1afc0a5c9
Revises: 7181475e1422
Create Date: 2026-10-11 06:16:14.191519

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '4eb1afc0a5c9'
down_revision: Union[str, None] = '7181475e1422'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Lessons: a separate "the user actually played this pass to the end"
    # flag the "lessons_completed" achievement counts, so a lesson that
    # auto-completes from already-known words no longer earns it.
    op.add_column(
        "lessons",
        sa.Column("completed_by_pass", sa.Boolean(), nullable=False, server_default=sa.text("false")),
    )
    # Past completions were genuine playthroughs (is_completed only ever
    # flipped while playing), so backfill them rather than punish existing
    # users; going forward only finish_lesson_pass sets it.
    op.execute("UPDATE lessons SET completed_by_pass = true WHERE is_completed = true")

    # Phrases: real opens, counted once per (user, phrase).
    op.create_table(
        "user_phrase_opens",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column(
            "phrase_id",
            sa.Integer(),
            sa.ForeignKey("phrases.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("user_id", "phrase_id", name="uq_user_phrase_open"),
    )


def downgrade() -> None:
    op.drop_table("user_phrase_opens")
    op.drop_column("lessons", "completed_by_pass")
