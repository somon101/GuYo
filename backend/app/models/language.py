"""Языки платформы -- реестр, который можно менять из админки.

До этой таблицы языки были ЗАШИТЫ В КОД (`app/core/languages.py`,
`UI_LANGUAGES`, `READING_LANGUAGES`): добавить китайский, немецкий или арабский
без программиста было нельзя. А по смыслу язык -- это просто ещё один слой
записей поверх общих понятий (у понятия №705 есть `Человек` / `одам` /
`Odam` / `person`), поэтому и заводиться он должен одной строкой в базе.

Что здесь живёт: код языка (совпадает с `word_entries.language`,
`word_entry_forms.language`, `phrase_entries.language`), название для админки,
самоназвание для людей, алфавит для упражнений с буквами и включён ли язык.

Чего здесь НЕТ: перечисления слов. Слова -- это языковые записи понятий, они
появляются, когда язык наполняют (вручную, импортом или ИИ).
"""

from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Language(Base):
    __tablename__ = "languages"

    # Код и есть первичный ключ: именно он лежит в языковых записях, поэтому
    # второй колонки-идентификатора не нужно.
    code: Mapped[str] = mapped_column(String(8), primary_key=True)
    # Название для админки: «Немецкий».
    name: Mapped[str] = mapped_column(String(64), nullable=False)
    # Как язык называет себя: «Deutsch», «Тоҷикӣ». Показывается людям.
    native_name: Mapped[str | None] = mapped_column(String(64), nullable=True)
    # Буквы для упражнений «Собери слово»; у каждого языка свой.
    alphabet: Mapped[str | None] = mapped_column(String(256), nullable=True)
    # Выключенный язык остаётся со своими записями, но не предлагается людям.
    is_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    # Порядок в списках: русский первым, дальше по возрастанию.
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
