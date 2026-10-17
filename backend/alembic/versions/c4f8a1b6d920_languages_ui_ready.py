"""Языки интерфейса переезжают в базу: languages.ui_ready

Языки уже живут в таблице (languages), но список ЯЗЫКОВ ИНТЕРФЕЙСА был зашит
в коде на четыре штуки. Теперь у языка есть признак «интерфейс переведён»:
админка может убрать язык из переключателя интерфейса, не трогая код
приложения, и вернуть обратно, когда перевод будет готов.

Сам перевод строк этот признак не создаёт -- он только говорит, предлагать ли
язык человеку.

Revision ID: c4f8a1b6d920
Revises: b7d1e4a9c310
"""

from alembic import op
import sqlalchemy as sa

revision = "c4f8a1b6d920"
down_revision = "b7d1e4a9c310"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    columns = {c["name"] for c in sa.inspect(bind).get_columns("languages")}
    if "ui_ready" not in columns:
        op.add_column(
            "languages",
            sa.Column("ui_ready", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        )
    # По умолчанию НЕ переведён: у нового языка строк в приложении нет.
    # Переведены только те четыре, что реально есть в сборке.
    op.execute("update languages set ui_ready = false")
    op.execute("update languages set ui_ready = true where code in ('ru', 'tg', 'uz', 'en')")


def downgrade() -> None:
    bind = op.get_bind()
    columns = {c["name"] for c in sa.inspect(bind).get_columns("languages")}
    if "ui_ready" in columns:
        op.drop_column("languages", "ui_ready")
