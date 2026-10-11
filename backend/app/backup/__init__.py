"""Full backup and restore: every table of the database plus every stored
media file (audio, images, avatars) in one ZIP.

    backup.zip
      manifest.json        alembic revision, time, row counts
      tables/<name>.json   all rows of each table
      media/<key>          every file under MEDIA_ROOT

Made by GET /admin/backup (app/routers/admin_backup.py); restored with
`python -m app.backup.restore <zip>` into an empty, migrated database.
Plain JSON, so it does not depend on pg_dump or a Postgres version.
"""

import base64
import datetime as dt
import decimal
import json
import tempfile
import uuid
import zipfile
from pathlib import Path

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.storage import MEDIA_ROOT
from app.database import Base


def _encode(value):
    if isinstance(value, (dt.datetime, dt.date, dt.time)):
        return {"__t": type(value).__name__, "v": value.isoformat()}
    if isinstance(value, decimal.Decimal):
        return {"__t": "decimal", "v": str(value)}
    if isinstance(value, uuid.UUID):
        return str(value)
    if isinstance(value, (bytes, bytearray, memoryview)):
        return {"__t": "bytes", "v": base64.b64encode(bytes(value)).decode()}
    raise TypeError(f"Cannot back up value of type {type(value)}")


def _decode(obj):
    kind = obj.get("__t") if isinstance(obj, dict) else None
    if kind == "datetime":
        return dt.datetime.fromisoformat(obj["v"])
    if kind == "date":
        return dt.date.fromisoformat(obj["v"])
    if kind == "time":
        return dt.time.fromisoformat(obj["v"])
    if kind == "decimal":
        return decimal.Decimal(obj["v"])
    if kind == "bytes":
        return base64.b64decode(obj["v"])
    return obj


def make_backup(db: Session) -> Path:
    """Writes the backup to a temporary file and returns its path."""
    import app.models  # noqa: F401  -- every table registered on Base

    revision = db.execute(text("SELECT version_num FROM alembic_version")).scalar()
    out = Path(tempfile.mkstemp(suffix=".zip")[1])
    counts = {}
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for table in Base.metadata.sorted_tables:
            rows = [dict(r._mapping) for r in db.execute(table.select())]
            counts[table.name] = len(rows)
            z.writestr(f"tables/{table.name}.json", json.dumps(rows, default=_encode, ensure_ascii=False))
        files = 0
        if MEDIA_ROOT.exists():
            for path in MEDIA_ROOT.rglob("*"):
                if path.is_file():
                    # Already-compressed audio/images: store, don't re-deflate.
                    z.write(path, f"media/{path.relative_to(MEDIA_ROOT).as_posix()}", zipfile.ZIP_STORED)
                    files += 1
        z.writestr(
            "manifest.json",
            json.dumps(
                {
                    "created_at": dt.datetime.now(dt.timezone.utc).isoformat(),
                    "alembic_revision": revision,
                    "rows": counts,
                    "media_files": files,
                },
                ensure_ascii=False,
                indent=1,
            ),
        )
    return out


def restore_backup(db: Session, zip_path: Path) -> dict:
    """Loads a backup into an EMPTY database already migrated to the same
    alembic revision, and copies the media files into MEDIA_ROOT."""
    import app.models  # noqa: F401

    with zipfile.ZipFile(zip_path) as z:
        manifest = json.loads(z.read("manifest.json"))
        current = db.execute(text("SELECT version_num FROM alembic_version")).scalar()
        if current != manifest["alembic_revision"]:
            raise SystemExit(
                f"База на миграции {current}, а копия сделана на {manifest['alembic_revision']}. "
                "Сначала: alembic upgrade " + str(manifest["alembic_revision"])
            )
        names = set(z.namelist())
        # Clear seeded defaults (admin, settings rows), children first.
        for table in reversed(Base.metadata.sorted_tables):
            db.execute(table.delete())
        for table in Base.metadata.sorted_tables:
            member = f"tables/{table.name}.json"
            if member not in names:
                continue
            rows = json.loads(z.read(member), object_hook=_decode)
            if rows:
                db.execute(table.insert(), rows)
        # Postgres: move every id sequence past the restored rows.
        if db.bind.dialect.name == "postgresql":
            for table in Base.metadata.sorted_tables:
                if "id" in table.c and table.c.id.autoincrement and str(table.c.id.type) == "INTEGER":
                    db.execute(
                        text(
                            f"SELECT setval(pg_get_serial_sequence('{table.name}', 'id'), "
                            f"COALESCE((SELECT MAX(id) FROM {table.name}), 0) + 1, false)"
                        )
                    )
        db.commit()
        files = 0
        for name in names:
            if name.startswith("media/") and not name.endswith("/"):
                target = MEDIA_ROOT / name[len("media/"):]
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(z.read(name))
                files += 1
    return {"rows": manifest["rows"], "media_files": files}
