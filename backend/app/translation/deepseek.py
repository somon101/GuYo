"""The AI translator: fills the missing Uzbek or English translations of
words (a "uz"/"en" WordTranslation) and phrases (Phrase.translation_uz /
translation_en) through the DeepSeek API, from both the Russian original
and its Tajik translation. One language per run, picked by the admin.

Its key and progress live on the single LearningSettings row, so Admin Web
only polls that row (same idea as ImportJob) and a run survives the admin
closing the tab. One run at a time, in a daemon thread with its own session.
Results go live immediately; an admin can still edit any of them by hand.
"""

import json
import logging
import threading

import requests
from sqlalchemy.orm import Session

from app.models.learning_settings import LearningSettings
from app.models.phrase import Phrase
from app.models.word import Word, WordTranslation

log = logging.getLogger(__name__)

API_URL = "https://api.deepseek.com/chat/completions"
MODEL = "deepseek-chat"
BATCH = 25

# Languages the translator can fill, with how the prompt names them.
LANGUAGES = {
    "uz": "Uzbek (Latin script, modern standard spelling with oʻ and gʻ)",
    "en": "English (natural, modern, neutral register)",
}


def _prompt(lang: str) -> str:
    return (
        f"You translate vocabulary for a Russian-learning app into {LANGUAGES[lang]}. "
        'Each item has the Russian original ("ru") and its Tajik translation ("tg"), '
        "which shows the intended meaning. Translate the Russian with the same meaning "
        "and register; for a single word give one short translation, no explanations. "
        f'Answer only with JSON: {{"items": [{{"id": <id>, "{lang}": "<translation>"}}]}} with every id.'
    )


def _phrase_column(lang: str) -> str:
    return f"translation_{lang}"

_lock = threading.Lock()


def settings_row(db: Session) -> LearningSettings:
    row = db.get(LearningSettings, 1)
    if row is None:
        row = LearningSettings(id=1)
        db.add(row)
        db.flush()
    return row


def _tajik(word: Word) -> str:
    return next((t.text for t in word.translations if t.language == "tg"), "")


def missing_words(db: Session, lang: str) -> list[Word]:
    return [w for w in db.query(Word).order_by(Word.id).all() if not any(t.language == lang for t in w.translations)]


def missing_phrases(db: Session, lang: str) -> list[Phrase]:
    column = getattr(Phrase, _phrase_column(lang))
    return db.query(Phrase).filter(column.is_(None)).order_by(Phrase.id).all()


def translate_batch(api_key: str, items: list[dict], lang: str) -> dict[int, str]:
    response = requests.post(
        API_URL,
        headers={"Authorization": f"Bearer {api_key}"},
        json={
            "model": MODEL,
            "temperature": 0.2,
            "response_format": {"type": "json_object"},
            "messages": [
                {"role": "system", "content": _prompt(lang)},
                {"role": "user", "content": json.dumps({"items": items}, ensure_ascii=False)},
            ],
        },
        timeout=120,
    )
    if response.status_code == 401:
        raise RuntimeError("DeepSeek отклонил ключ (401)")
    if response.status_code == 402:
        raise RuntimeError("На счёте DeepSeek закончились деньги (402)")
    response.raise_for_status()
    content = response.json()["choices"][0]["message"]["content"]
    out = {}
    for item in json.loads(content).get("items", []):
        text = str(item.get(lang) or "").strip()
        if text and isinstance(item.get("id"), int):
            out[item["id"]] = text[:1000]
    return out


def _run() -> None:
    from app.database import SessionLocal

    db = SessionLocal()
    try:
        row = settings_row(db)
        key = row.deepseek_api_key or ""
        lang = row.translate_language
        words, phrases = missing_words(db, lang), missing_phrases(db, lang)
        row.translate_total = len(words) + len(phrases)
        row.translate_done = row.translate_failed = 0
        db.commit()

        jobs = [("word", words[i : i + BATCH]) for i in range(0, len(words), BATCH)]
        jobs += [("phrase", phrases[i : i + BATCH]) for i in range(0, len(phrases), BATCH)]
        for kind, chunk in jobs:
            db.refresh(row)
            if row.translate_status != "running":
                return  # stopped by the admin
            if kind == "word":
                items = [{"id": w.id, "ru": w.word, "tg": _tajik(w)} for w in chunk]
            else:
                items = [{"id": p.id, "ru": p.original, "tg": p.translation_tg} for p in chunk]
            try:
                result = translate_batch(key, items, lang)
            except RuntimeError as e:
                row.translate_status, row.translate_error = "failed", str(e)
                db.commit()
                return
            except Exception as e:  # network hiccup: count the batch as failed, go on
                log.warning("DeepSeek batch failed: %s", e)
                result = {}
            for obj in chunk:
                text = result.get(obj.id)
                if text is None:
                    row.translate_failed += 1
                elif kind == "word":
                    db.add(WordTranslation(word_id=obj.id, language=lang, text=text))
                else:
                    setattr(obj, _phrase_column(lang), text)
            row.translate_done += len(chunk)
            db.commit()
        row.translate_status = "completed"
        db.commit()
    except Exception as e:
        log.exception("AI translation failed")
        db.rollback()
        row = settings_row(db)
        row.translate_status, row.translate_error = "failed", str(e)[:500]
        db.commit()
    finally:
        db.close()
        _lock.release()


def start(db: Session, lang: str) -> bool:
    """Starts a run into `lang`; False when one is already going."""
    if not _lock.acquire(blocking=False):
        return False
    row = settings_row(db)
    row.translate_status, row.translate_error, row.translate_language = "running", None, lang
    db.commit()
    threading.Thread(target=_run, daemon=True).start()
    return True
