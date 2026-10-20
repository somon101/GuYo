"""Words have no points any more: drop every column and table of the old
points system (word score, points per exercise, the learned threshold, the
points ranges of word levels and the weighted Priority formula).

Learned is word_progress.mastered_at; levels and Priority come from the
memory model. downgrade() brings the columns back empty (defaults only).

Revision ID: f3b5d7f9a1c4
Revises: e2a4c6e8f0b3
"""

import sqlalchemy as sa
from alembic import op

revision: str = "f3b5d7f9a1c4"
down_revision: str | None = "e2a4c6e8f0b3"
branch_labels = None
depends_on = None

PRIORITY_WEIGHTS = [
    ("weight_level", sa.Float(), "1"),
    ("weight_recent_errors", sa.Float(), "1"),
    ("weight_recency", sa.Float(), "1"),
    ("weight_stability", sa.Float(), "1"),
    ("window5_weight", sa.Float(), "1"),
    ("window10_weight", sa.Float(), "0.6"),
    ("window20_weight", sa.Float(), "0.3"),
    ("stability_window", sa.Integer(), "10"),
    ("memory_enabled", sa.Boolean(), "true"),
]


def upgrade() -> None:
    # Named differently (or missing) on some databases; dropping the column
    # would take it along anyway.
    op.execute("ALTER TABLE word_progress DROP CONSTRAINT IF EXISTS ck_word_progress_score_range")
    op.drop_column("word_progress", "score")
    op.drop_column("word_attempts", "score_after")
    op.drop_column("review_list_words", "score")
    op.drop_column("exercise_settings", "correct_points")
    op.drop_column("exercise_settings", "incorrect_points")
    op.drop_column("learning_settings", "threshold_score")
    op.execute("ALTER TABLE word_levels DROP CONSTRAINT IF EXISTS ck_word_level_range_valid")
    op.drop_column("word_levels", "min_points")
    op.drop_column("word_levels", "max_points")
    op.drop_column("word_levels", "priority_weight")
    for name, _, _ in PRIORITY_WEIGHTS:
        op.drop_column("priority_settings", name)
    op.drop_table("priority_recency_bands")
    op.drop_table("priority_stability_bands")


def downgrade() -> None:
    op.create_table(
        "priority_stability_bands",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("min_percent", sa.Integer(), nullable=False),
        sa.Column("max_percent", sa.Integer(), nullable=False),
        sa.Column("contribution", sa.Float(), server_default="0", nullable=False),
        sa.Column("order", sa.Integer(), server_default="0", nullable=False),
        sa.Column("enabled", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.CheckConstraint("max_percent >= min_percent", name="ck_priority_stability_range_valid"),
    )
    op.create_table(
        "priority_recency_bands",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("min_days", sa.Integer(), nullable=False),
        sa.Column("max_days", sa.Integer(), nullable=True),
        sa.Column("contribution", sa.Float(), server_default="0", nullable=False),
        sa.Column("order", sa.Integer(), server_default="0", nullable=False),
        sa.Column("enabled", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.CheckConstraint("max_days IS NULL OR max_days >= min_days", name="ck_priority_recency_range_valid"),
    )
    for name, type_, default in PRIORITY_WEIGHTS:
        op.add_column("priority_settings", sa.Column(name, type_, server_default=default, nullable=False))
    op.add_column("word_levels", sa.Column("priority_weight", sa.Float(), server_default="0", nullable=False))
    op.add_column("word_levels", sa.Column("max_points", sa.Integer(), nullable=True))
    op.add_column("word_levels", sa.Column("min_points", sa.Integer(), server_default="0", nullable=False))
    op.add_column("learning_settings", sa.Column("threshold_score", sa.Integer(), server_default="60", nullable=False))
    op.add_column("exercise_settings", sa.Column("incorrect_points", sa.Integer(), nullable=True))
    op.add_column("exercise_settings", sa.Column("correct_points", sa.Integer(), nullable=True))
    op.add_column("review_list_words", sa.Column("score", sa.Integer(), server_default="0", nullable=False))
    op.add_column("word_attempts", sa.Column("score_after", sa.Integer(), server_default="0", nullable=False))
    op.add_column("word_progress", sa.Column("score", sa.Integer(), server_default="0", nullable=False))
    op.create_check_constraint("ck_word_progress_score_range", "word_progress", "score >= 0 AND score <= 100")
