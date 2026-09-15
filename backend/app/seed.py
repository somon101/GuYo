"""Idempotent seed: creates the one initial admin account (admin / 123456
by default, overridable via SEED_ADMIN_LOGIN / SEED_ADMIN_PASSWORD env vars).

Run with:  python -m app.seed
"""
from app.config import get_settings
from app.core.security import hash_password
from app.database import SessionLocal
from app.models.admin import Admin

settings = get_settings()


def seed_admin() -> None:
    db = SessionLocal()
    try:
        existing = db.query(Admin).filter(Admin.login == settings.seed_admin_login).first()
        if existing is not None:
            print(f"[seed] admin '{settings.seed_admin_login}' already exists, skipping")
            return

        admin = Admin(
            login=settings.seed_admin_login,
            password_hash=hash_password(settings.seed_admin_password),
        )
        db.add(admin)
        db.commit()
        print(f"[seed] created admin '{settings.seed_admin_login}'")
    finally:
        db.close()


if __name__ == "__main__":
    seed_admin()
