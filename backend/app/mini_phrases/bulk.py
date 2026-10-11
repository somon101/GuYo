"""Bulk mini-phrase generation as a background job.

Hundreds of phrases take far longer than one HTTP request, so the admin
starts a job and polls its progress. The job repeats small batches --
generate → script check → AI critic with stars → AI fixes (see
generate.generate) -- and saves only phrases that are valid, not too
similar to anything already saved, and rated MIN_STARS+ by the critic.
Each batch is saved right away, so the next batch sees it (no repeats) and
a stopped job keeps what it made. Topics rotate batch by batch for variety.

Jobs live in memory: a server restart (e.g. a deploy) ends a running job;
whatever was saved stays saved.
"""

import json
import os
import tempfile
import threading
import time
import uuid

from fastapi import HTTPException

from app.database import SessionLocal
from app.mini_phrases import generate as g
from app.models.category import Category
from app.models.dictionary import Dictionary

BATCH = 25
# Stop when this many batches in a row bring nothing new: the dictionary has
# run out of good material, more attempts only burn tokens.
MAX_EMPTY_BATCHES = 6
# A running job writes at least this often; older = its process is gone.
STALE_AFTER = 600

# The server runs several worker processes, so a job's state is a small JSON
# file every worker can read; only the worker running the job writes it.
_DIR = os.path.join(tempfile.gettempdir(), "guyo_mini_phrase_jobs")
os.makedirs(_DIR, exist_ok=True)
_lock = threading.Lock()


def _path(job_id: str) -> str:
    return os.path.join(_DIR, f"{''.join(c for c in job_id if c.isalnum())}.json")


def _write(job: dict) -> None:
    job["updated_at"] = time.time()
    tmp = _path(job["id"]) + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(job, f, ensure_ascii=False)
    os.replace(tmp, _path(job["id"]))


def get(job_id: str) -> dict | None:
    try:
        with open(_path(job_id), encoding="utf-8") as f:
            job = json.load(f)
    except (OSError, ValueError):
        return None
    if job["state"] == "running" and time.time() - job.get("updated_at", 0) > STALE_AFTER:
        job["state"] = "failed"
        job["error"] = "Задача прервалась (сервер перезапускался). Сохранённые фразы остались — запустите снова."
    job["cancel"] = os.path.exists(_path(job_id) + ".cancel")
    return job


def running_for(dictionary_id: int) -> dict | None:
    for name in os.listdir(_DIR):
        if name.endswith(".json"):
            job = get(name[:-5])
            if job and job["dictionary_id"] == dictionary_id and job["state"] == "running":
                return job
    return None


def latest_for(dictionary_id: int) -> dict | None:
    jobs = [get(n[:-5]) for n in os.listdir(_DIR) if n.endswith(".json")]
    jobs = [j for j in jobs if j and j["dictionary_id"] == dictionary_id]
    return max(jobs, key=lambda j: j["started_at"]) if jobs else None


def cancel(job_id: str) -> None:
    if get(job_id):
        open(_path(job_id) + ".cancel", "w").close()


def start(dictionary_id: int, target: int, category_id: int | None) -> dict:
    with _lock:
        existing = running_for(dictionary_id)
        if existing:
            return existing
        job = {
            "id": uuid.uuid4().hex[:12],
            "dictionary_id": dictionary_id,
            "target": target,
            "category_id": category_id,
            "state": "running",
            "saved": 0,
            "batches": 0,
            "rejected": 0,
            "tokens": 0,
            "forms_added": 0,
            "templates_created": 0,
            "recent": [],
            "message": "Запуск…",
            "error": None,
            "started_at": time.time(),
        }
        _write(job)
    threading.Thread(target=_run, args=(job["id"],), daemon=True).start()
    return job


def _run(job_id: str) -> None:
    job = get(job_id)
    job.pop("cancel", None)
    cancelled = lambda: os.path.exists(_path(job_id) + ".cancel")  # noqa: E731

    def update(**fields) -> None:
        job.update(fields)
        _write(job)

    db = SessionLocal()
    try:
        dictionary = db.get(Dictionary, job["dictionary_id"])
        if job["category_id"] is not None:
            topics: list[int | None] = [job["category_id"]]
        else:
            # All topics in turn, with a mixed batch between them.
            ids = [c for (c,) in db.query(Category.id).filter(Category.dictionary_id == dictionary.id).order_by(Category.id)]
            topics = []
            for c in ids:
                topics += [c, None]
            topics = topics or [None]
        empty_in_row = 0
        while job["saved"] < job["target"] and not cancelled():
            topic = topics[job["batches"] % len(topics)]
            n = min(BATCH, max(10, job["target"] - job["saved"] + 5))
            update(message=f"Пачка {job['batches'] + 1}: ИИ составляет, оценивает и исправляет фразы…")
            try:
                res = g.generate(db, dictionary, n, topic)
            except HTTPException as e:
                db.rollback()
                if e.status_code == 400:  # no key, no money, rejected key, no words: retrying won't help
                    update(state="failed", error=str(e.detail))
                    return
                update(message=f"Ошибка DeepSeek ({e.detail}), повтор через 20 с…")
                time.sleep(20)
                continue
            good = [i for i in res["items"] if i["valid"] and not i["too_similar"] and i.get("stars", 0) >= g.MIN_STARS]
            good = good[: job["target"] - job["saved"]]
            report = g.save(db, dictionary, good) if good else {"created": [], "forms_added": [], "templates_created": []}
            db.commit()
            created = report["created"]
            empty_in_row = 0 if created else empty_in_row + 1
            update(
                batches=job["batches"] + 1,
                saved=job["saved"] + len(created),
                rejected=job["rejected"] + res.get("dropped", 0) + len(res["items"]) - len(created),
                tokens=job["tokens"] + res["tokens"],
                forms_added=job["forms_added"] + len(report["forms_added"]),
                templates_created=job["templates_created"] + len(report["templates_created"]),
                recent=(created[::-1] + job["recent"])[:40],
            )
            if empty_in_row >= MAX_EMPTY_BATCHES:
                update(
                    state="done",
                    message=f"Остановлено: {MAX_EMPTY_BATCHES} пачек подряд без новых хороших фраз — в словаре не "
                    "хватает слов. Добавьте слова (вкладка «Слова») и запустите снова.",
                )
                return
        update(state="cancelled" if cancelled() else "done", message="Остановлено вами" if cancelled() else "Готово")
    except Exception as e:  # noqa: BLE001 -- a job must always end with a state
        db.rollback()
        update(state="failed", error=f"Сбой: {e}")
    finally:
        db.close()
