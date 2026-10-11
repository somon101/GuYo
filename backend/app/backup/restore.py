"""Restores a GuYo backup ZIP into the database in DATABASE_URL.

    alembic upgrade head        # an empty database, migrated
    python -m app.backup.restore path/to/guyo-backup.zip [path/to/media]

Everything already in that database is replaced.
"""

import sys
from pathlib import Path

from app.backup import restore_backup
from app.database import SessionLocal


def main() -> None:
    if len(sys.argv) not in (2, 3):
        raise SystemExit("Usage: python -m app.backup.restore <backup.zip> [media_dir]")
    media_dir = Path(sys.argv[2]) if len(sys.argv) == 3 else None
    db = SessionLocal()
    try:
        result = restore_backup(db, Path(sys.argv[1]), media_dir)
    finally:
        db.close()
    print(f"Restored {sum(result['rows'].values())} rows and {result['media_files']} files.")


if __name__ == "__main__":
    main()
