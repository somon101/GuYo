"""Удаление аккаунта: отметка, восстановление и окончательная чистка.

Google Play требует, чтобы аккаунт можно было удалить изнутри приложения, не
письмом в поддержку. Удаляем с окном в 30 дней: строка помечается
`deleted_at`, человек сразу исчезает отовсюду (рейтинг, друзья, поиск), а
вход по его логину и паролю возвращает всё обратно. Через 30 дней
`python -m app.account_deletion purge` удаляет строку окончательно вместе со
всеми её данными -- все таблицы ссылаются на users с ON DELETE CASCADE.

Почему не удаляем сразу: человек, удаливший аккаунт случайно (или в сердцах),
иначе теряет весь прогресс навсегда. Окно даёт шанс передумать и ничего не
стоит: пока аккаунт помечен, его никто не видит.
"""

import sys
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.models.user import User

# Сколько дней аккаунт можно вернуть.
DELETION_GRACE_DAYS = 30


def now() -> datetime:
    return datetime.now(timezone.utc)


def grace_deadline(user: User) -> datetime | None:
    """Когда аккаунт удалят окончательно. None -- аккаунт не удалён."""
    if user.deleted_at is None:
        return None
    deleted = user.deleted_at
    if deleted.tzinfo is None:
        deleted = deleted.replace(tzinfo=timezone.utc)
    return deleted + timedelta(days=DELETION_GRACE_DAYS)


def mark_deleted(db: Session, user: User) -> None:
    """Помечает аккаунт удалённым. Второй вызов ничего не портит."""
    if user.deleted_at is None:
        user.deleted_at = now()
        db.commit()


def restore_if_deleted(db: Session, user: User) -> bool:
    """Возвращает аккаунт, если он был удалён и окно ещё не вышло.

    Возвращает True, если аккаунт восстановлен."""
    deadline = grace_deadline(user)
    if deadline is None:
        return False
    if now() > deadline:
        # Окно вышло: данные ещё здесь (purge мог не дойти), но возвращать
        # уже нечего -- человек сам выбрал удаление 30 дней назад.
        return False
    user.deleted_at = None
    db.commit()
    return True


def is_deleted(user: User) -> bool:
    return user.deleted_at is not None


def purge_expired(db: Session) -> int:
    """Удаляет аккаунты, у которых окно восстановления вышло."""
    cutoff = now() - timedelta(days=DELETION_GRACE_DAYS)
    rows = (
        db.query(User)
        .filter(User.deleted_at.isnot(None), User.deleted_at < cutoff)
        .all()
    )
    removed = 0
    for user in rows:
        db.delete(user)
        removed += 1
    if removed:
        db.commit()
    return removed


def main(argv: list[str]) -> int:
    command = argv[1] if len(argv) > 1 else "purge"
    db = SessionLocal()
    try:
        if command == "purge":
            removed = purge_expired(db)
            print(f"[account-deletion] удалено окончательно: {removed}")
            return 0
        if command == "list":
            rows = db.query(User).filter(User.deleted_at.isnot(None)).order_by(User.deleted_at).all()
            print(f"[account-deletion] помечено удалёнными: {len(rows)}")
            for user in rows:
                print(f"  id={user.id} логин={user.login} вернуть до {grace_deadline(user):%Y-%m-%d}")
            return 0
        print("Использование: python -m app.account_deletion [purge|list]")
        return 2
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
