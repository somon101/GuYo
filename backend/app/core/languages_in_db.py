"""Рабочий список языков -- из таблицы languages, а не из кода.

Языки живут в базе и правятся в админке, поэтому «какие языки существуют»
должен отвечать именно этот модуль. Раньше ответ был зашит в двух кортежах
(`UI_LANGUAGES`, `READING_LANGUAGES`), и добавленный язык нигде не появлялся,
пока программист не выпустит новую сборку.

Кэш: список спрашивают на каждый запрос (проверка «родной ≠ изучаемый»,
выбор перевода), а меняется он раз в месяц. Держим его в памяти
`CACHE_TTL` секунд -- этого достаточно, чтобы правка в админке подхватилась
почти сразу, и при этом база не получала запрос на каждый вызов.
"""

import time

from app.database import SessionLocal
from app.models.language import Language

CACHE_TTL = 30.0

# (момент чтения, включённые языки, языки с переведённым интерфейсом)
_cache: tuple[float, frozenset[str], frozenset[str]] | None = None


def _load() -> tuple[frozenset[str], frozenset[str]]:
    db = SessionLocal()
    try:
        rows = db.query(Language.code, Language.is_enabled, Language.ui_ready).all()
    finally:
        db.close()
    known = frozenset(code for code, enabled, _ in rows if enabled)
    ui_ready = frozenset(code for code, enabled, ready in rows if enabled and ready)
    return known, ui_ready


def _cached() -> tuple[frozenset[str], frozenset[str]]:
    global _cache
    now = time.monotonic()
    if _cache is not None and now - _cache[0] < CACHE_TTL:
        return _cache[1], _cache[2]
    try:
        known, ui_ready = _load()
    except Exception:
        # База недоступна: отдаём пустое множество, вызывающий возьмёт
        # запасной список из кода. Языки -- не то, ради чего стоит ронять
        # запрос.
        return frozenset(), frozenset()
    _cache = (now, known, ui_ready)
    return known, ui_ready


def known_codes() -> frozenset[str]:
    """Все включённые языки: на них можно учить и с них можно читать."""
    return _cached()[0]


def ui_ready_codes() -> frozenset[str]:
    """Языки, интерфейс которых переведён: их можно предлагать в переключателе."""
    return _cached()[1]


def forget() -> None:
    """Сбрасывает кэш -- вызывается после правки языка в админке."""
    global _cache
    _cache = None
