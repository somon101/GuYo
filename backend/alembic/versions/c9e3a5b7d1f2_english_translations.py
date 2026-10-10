"""English as a translation language: phrases.translation_en, translator language

Revision ID: c9e3a5b7d1f2
Revises: b8d2f4a6c0e1
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "c9e3a5b7d1f2"
down_revision: Union[str, None] = "b8d2f4a6c0e1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("phrases", sa.Column("translation_en", sa.String(1000), nullable=True))
    op.add_column(
        "learning_settings",
        sa.Column("translate_language", sa.String(8), nullable=False, server_default="uz"),
    )


def downgrade() -> None:
    op.drop_column("learning_settings", "translate_language")
    op.drop_column("phrases", "translation_en")
