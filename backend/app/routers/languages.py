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
    """Включённые языки: код, название и самоназвание."""
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
        }
        for row in rows
    ]
