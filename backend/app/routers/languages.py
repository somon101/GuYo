"""Языки для приложения: что человек может выбрать.

Отдаём только включённые языки и в порядке, заданном в админке. Приложение
показывает этот список в переключателе на главном экране, поэтому здесь нет
ничего административного -- ни счётчиков, ни алфавитов.
"""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.language import Language

router = APIRouter(prefix="/languages", tags=["languages"])


@router.get("")
def list_languages(db: Session = Depends(get_db)):
    """Включённые языки: код, название, самоназвание и переведён ли интерфейс.

    `ui_ready` -- единственное, что решает, предлагать ли язык в переключателе
    интерфейса приложения. Язык без перевода строк остаётся доступным как
    родной и как изучаемый: это разные вещи."""
    rows = (
        db.query(Language)
        .filter(Language.is_enabled.is_(True))
        .order_by(Language.sort_order, Language.code)
        .all()
    )
    return [
        {
            "code": row.code,
            "name": row.name,
            "native_name": row.native_name or row.name,
            "ui_ready": row.ui_ready,
            # Только опубликованное можно выбрать: изучать (`learnable`) и
            # читать подсказки на нём (`native_ok`) -- app/languages/readiness.py.
            "learnable": row.learn_published,
            "native_ok": row.native_published,
        }
        for row in rows
    ]
