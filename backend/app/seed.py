"""Idempotent seed: creates the one initial admin account (admin / 123456
by default, overridable via SEED_ADMIN_LOGIN / SEED_ADMIN_PASSWORD env vars)
and, the first time the rating system has no ranks configured at all, the 7
standard ranks (Bronze..Grand Master) with their own uploaded icons -- same
"admin can add/replace/delete/rename/recolor freely afterwards" rules as any
other Rank row; this only ever fires once, when the table is empty.

Run with:  python -m app.seed
"""
from pathlib import Path

from app.config import get_settings
from app.core.security import hash_password
from app.core.storage import save_bytes
from app.database import SessionLocal
from app.models.admin import Admin
from app.models.rating import Rank

settings = get_settings()

SEED_ASSETS_DIR = Path(__file__).parent / "seed_assets" / "ranks"

# (name, min_points, max_points, color, icon filename) -- a sensible
# starting ladder, not load-bearing: the admin can freely rename, re-range,
# recolor, or re-icon any of these afterwards in Admin Web, exactly like a
# rank created by hand.
DEFAULT_RANKS: list[tuple[str, int, int | None, str, str]] = [
    ("Бронза", 0, 99, "#CD7F32", "bronze.png"),
    ("Серебро", 100, 299, "#9FAEC2", "silver.png"),
    ("Золото", 300, 599, "#FFC93C", "gold.png"),
    ("Платина", 600, 999, "#7FB1E3", "platinum.png"),
    ("Алмаз", 1000, 1999, "#22D3EE", "diamond.png"),
    ("Мастер", 2000, 3999, "#8B5CF6", "master.png"),
    ("Грандмастер", 4000, None, "#F59E0B", "grandmaster.png"),
]


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


def seed_ranks() -> None:
    db = SessionLocal()
    try:
        if db.query(Rank).first() is not None:
            print("[seed] ranks already configured, skipping")
            return

        for order, (name, min_points, max_points, color, icon_filename) in enumerate(DEFAULT_RANKS):
            icon_path = SEED_ASSETS_DIR / icon_filename
            icon_key = None
            if icon_path.is_file():
                icon_key = save_bytes(icon_path.read_bytes(), subdir="ranks/icons", filename_hint=icon_filename)
            db.add(
                Rank(
                    name=name,
                    min_points=min_points,
                    max_points=max_points,
                    color=color,
                    icon_key=icon_key,
                    order=order,
                    enabled=True,
                )
            )
        db.commit()
        print(f"[seed] created {len(DEFAULT_RANKS)} default ranks")
    finally:
        db.close()


if __name__ == "__main__":
    seed_admin()
    seed_ranks()
