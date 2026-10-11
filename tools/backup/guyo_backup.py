"""Backs up GuYo from the server to this folder:

  db/guyo-backup_<date>.zip   the whole database (newest 30 kept)
  media/...                   every audio/image/photo file, mirrored --
                              only files not here yet are downloaded

Settings come from the environment, else from admin.txt next to this
script (two lines: login, password) -- never from the code:
  GUYO_SERVER, GUYO_ADMIN_LOGIN, GUYO_ADMIN_PASSWORD, BACKUP_DIR

Used by the PC's daily task (the GuYo-backups folder) and by the
GitHub Actions cloud backup (.github/workflows/backup.yml).
"""

import json
import os
import sys
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

SERVER = os.environ.get("GUYO_SERVER", "https://backend-production-cda3.up.railway.app")
KEEP = 30

FOLDER = Path(os.environ.get("BACKUP_DIR") or Path(__file__).resolve().parent)


def _credentials() -> tuple[str, str]:
    login, password = os.environ.get("GUYO_ADMIN_LOGIN", "admin"), os.environ.get("GUYO_ADMIN_PASSWORD")
    if password:
        return login, password
    creds = Path(__file__).resolve().parent / "admin.txt"
    if creds.exists():
        lines = [l.strip() for l in creds.read_text(encoding="utf-8").splitlines() if l.strip()]
        if len(lines) >= 2:
            return lines[0], lines[1]
    raise SystemExit("Нет пароля админа: задайте GUYO_ADMIN_PASSWORD или создайте admin.txt (логин и пароль)")

DB_DIR = FOLDER / "db"
MEDIA_DIR = FOLDER / "media"


def _get(url: str, token: str, timeout: int = 300):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    return urllib.request.urlopen(req, timeout=timeout)


def _save(res, target: Path, expected: int | None = None) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_name(target.name + ".part")
    with open(partial, "wb") as f:
        while chunk := res.read(1024 * 1024):
            f.write(chunk)
    size = partial.stat().st_size
    if expected is not None and size != expected:
        partial.unlink()
        raise IOError(f"{target.name}: получено {size} из {expected} байт")
    partial.replace(target)


def main() -> None:
    login, password = _credentials()
    req = urllib.request.Request(
        f"{SERVER}/auth/admin/login",
        data=json.dumps({"login": login, "password": password}).encode(),
        headers={"Content-Type": "application/json"},
    )
    token = json.load(urllib.request.urlopen(req, timeout=60))["access_token"]

    # 1. Database
    print("База данных...")
    with _get(f"{SERVER}/admin/backup?media=false", token) as res:
        disposition = res.headers.get("Content-Disposition", "")
        name = disposition.split("filename=")[-1].strip('"') if "filename=" in disposition else "guyo-backup.zip"
        length = res.headers.get("Content-Length")
        target = DB_DIR / name
        _save(res, target, int(length) if length else None)
    with zipfile.ZipFile(target) as z:
        manifest = json.loads(z.read("manifest.json"))
    print(f"  {target.name}: {sum(manifest['rows'].values())} строк, {target.stat().st_size / 1024:.0f} КБ")
    for old in sorted(DB_DIR.glob("guyo-backup_*.zip"))[:-KEEP]:
        old.unlink()

    # 2. Media: only what is missing or changed
    with _get(f"{SERVER}/admin/backup/media", token) as res:
        index = json.load(res)
    todo = [f for f in index if not (MEDIA_DIR / f["key"]).exists() or (MEDIA_DIR / f["key"]).stat().st_size != f["size"]]
    print(f"Файлы: всего {len(index)}, новых {len(todo)}")
    failed = 0
    for i, f in enumerate(todo, 1):
        url = f"{SERVER}/media/{urllib.parse.quote(f['key'])}"
        try:
            with urllib.request.urlopen(url, timeout=120) as res:
                _save(res, MEDIA_DIR / f["key"], f["size"])
        except Exception as e:
            failed += 1
            print(f"  не скачан {f['key']}: {e}")
        if i % 50 == 0:
            print(f"  {i}/{len(todo)}")
    total_mb = sum(f["size"] for f in index) / 1024 / 1024
    print(f"Готово. Файлов {len(index)} ({total_mb:.0f} МБ), ошибок {failed}.")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("ОШИБКА:", e)
        sys.exit(1)
