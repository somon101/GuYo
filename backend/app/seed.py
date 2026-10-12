"""Idempotent seed: creates the one initial admin account (admin / 123456
by default, overridable via SEED_ADMIN_LOGIN / SEED_ADMIN_PASSWORD env vars)
and, the first time the rating system has no ranks configured at all, the 7
standard ranks (Bronze..Grand Master) with their own uploaded icons -- same
"admin can add/replace/delete/rename/recolor freely afterwards" rules as any
other Rank row; this only ever fires once, when the table is empty.

Run with:  python -m app.seed
"""
from pathlib import Path

from sqlalchemy import func

from app.config import get_settings
from app.core.security import hash_password
from app.core.storage import save_bytes
from app.database import SessionLocal
from app.models.achievement import Achievement
from app.models.admin import Admin
from app.models.rating import Rank
from app.models.status import StatusEmoji, StatusPhrase

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


STATUS_EMOJI_DIR = Path(__file__).parent / "seed_assets" / "status_emojis"

# GuYo's own status emoji (drawn for the app, so they look the same on
# every phone) and starter phrases. Seeded once, when each list is empty;
# the admin edits, disables or replaces them freely afterwards.
DEFAULT_STATUS_EMOJIS: list[tuple[str, str]] = [
    ("Огонь", "fire.png"),
    ("Корона", "crown.png"),
    ("Ракета", "rocket.png"),
    ("Молния", "bolt.png"),
    ("Кубок", "trophy.png"),
    ("Звезда", "star.png"),
    ("Алмаз", "diamond.png"),
    ("Цель", "target.png"),
    ("Крутой", "cool.png"),
    ("Первое место", "medal.png"),
]
DEFAULT_STATUS_PHRASES: list[str] = [
    "Я буду первым!",
    "Этот ранг будет моим",
    "Меня не догнать",
    "Я самый сильный",
    "Цель — топ-1",
    "Догоняй, если сможешь",
    "Каждый день — новый рекорд",
    "Учусь, пока другие отдыхают",
    "Ман аввал мешавам!",
    "Ман қавӣ ҳастам",
]


def seed_statuses() -> None:
    db = SessionLocal()
    try:
        if db.query(StatusEmoji).first() is None:
            for order, (name, filename) in enumerate(DEFAULT_STATUS_EMOJIS):
                path = STATUS_EMOJI_DIR / filename
                if not path.is_file():
                    continue
                key = save_bytes(path.read_bytes(), subdir="status/emojis", filename_hint=filename)
                db.add(StatusEmoji(name=name, image_key=key, order=order, enabled=True))
            print(f"[seed] created {len(DEFAULT_STATUS_EMOJIS)} status emojis")
        if db.query(StatusPhrase).first() is None:
            for order, text in enumerate(DEFAULT_STATUS_PHRASES):
                db.add(StatusPhrase(text=text, order=order, enabled=True))
            print(f"[seed] created {len(DEFAULT_STATUS_PHRASES)} status phrases")
        db.commit()
    finally:
        db.close()


# A starter catalog of achievements, grouped into chains by condition_type.
# Each entry: (condition_type, condition_value, title, description, color).
# Seeded per-row (matched on condition_type + condition_value), so adding
# new entries in a later deploy creates only the missing ones and never
# duplicates. Icons are left empty here -- the admin uploads them in Admin
# Web afterwards; title/slogan/color/icon/order are all editable there, so
# this is a convenient starting point, not a fixed structure.
#
# condition_type must be one of CONDITION_TYPES (app/achievements/
# conditions.py); points_earned/friends_added/quest_words_completed are the
# newest measures.
DEFAULT_ACHIEVEMENTS: list[tuple[str, int, str, str, str]] = [
    # Открытые фразы
    ("phrases_opened", 1, "Первая фраза", "Ты открыл свою первую фразу!", "#6366F1"),
    ("phrases_opened", 10, "Любитель фраз", "Открыто 10 фраз.", "#6366F1"),
    ("phrases_opened", 50, "Знаток фраз", "Открыто 50 фраз.", "#6366F1"),
    ("phrases_opened", 100, "Мастер фраз", "Открыто 100 фраз.", "#6366F1"),
    ("phrases_opened", 250, "Коллекционер фраз", "Открыто 250 фраз.", "#6366F1"),
    ("phrases_opened", 500, "Фразовый эксперт", "Открыто 500 фраз.", "#6366F1"),
    ("phrases_opened", 1000, "Тысяча фраз", "Открыто 1000 фраз.", "#6366F1"),
    # Изученные слова
    ("words_learned", 1, "Первое слово", "Начало положено!", "#0EA5E9"),
    ("words_learned", 25, "Запас растёт", "Изучено 25 слов.", "#0EA5E9"),
    ("words_learned", 100, "Сто слов", "Изучено 100 слов.", "#0EA5E9"),
    ("words_learned", 300, "Полиглот", "Изучено 300 слов.", "#0EA5E9"),
    ("words_learned", 500, "Ходячий словарь", "Изучено 500 слов.", "#0EA5E9"),
    ("words_learned", 1000, "Легенда словаря", "Изучено 1000 слов.", "#0EA5E9"),
    ("words_learned", 1500, "Словесный титан", "Изучено 1500 слов.", "#0EA5E9"),
    ("words_learned", 2000, "Живая энциклопедия", "Изучено 2000 слов.", "#0EA5E9"),
    # Пройденные мини-фразы
    ("mini_phrases_done", 1, "Первая мини-фраза", "Ты собрал свою первую мини-фразу!", "#14B8A6"),
    ("mini_phrases_done", 10, "Сборщик фраз", "Пройдено 10 мини-фраз.", "#14B8A6"),
    ("mini_phrases_done", 25, "Говорю по делу", "Пройдено 25 мини-фраз.", "#14B8A6"),
    ("mini_phrases_done", 50, "Уверенная речь", "Пройдено 50 мини-фраз.", "#14B8A6"),
    ("mini_phrases_done", 100, "Сто мини-фраз", "Пройдено 100 мини-фраз.", "#14B8A6"),
    ("mini_phrases_done", 250, "Мастер общения", "Пройдено 250 мини-фраз.", "#14B8A6"),
    ("mini_phrases_done", 500, "Мастер мини-фраз", "Пройдено 500 мини-фраз.", "#14B8A6"),
    # Пройденные уроки
    ("lessons_completed", 1, "Первый урок", "Первый урок пройден!", "#10B981"),
    ("lessons_completed", 5, "Входишь во вкус", "Пройдено 5 уроков.", "#10B981"),
    ("lessons_completed", 25, "Прилежный ученик", "Пройдено 25 уроков.", "#10B981"),
    ("lessons_completed", 50, "Полсотни уроков", "Пройдено 50 уроков.", "#10B981"),
    ("lessons_completed", 100, "Стобалльник", "Пройдено 100 уроков.", "#10B981"),
    ("lessons_completed", 200, "Марафонец", "Пройдено 200 уроков.", "#10B981"),
    # Серия дней активности
    ("streak_days", 3, "Три дня подряд", "3 дня активности подряд.", "#F97316"),
    ("streak_days", 7, "Неделя без пропусков", "7 дней активности подряд.", "#F97316"),
    ("streak_days", 14, "Две недели", "14 дней активности подряд.", "#F97316"),
    ("streak_days", 30, "Месяц дисциплины", "30 дней активности подряд.", "#F97316"),
    ("streak_days", 100, "Сто дней огня", "100 дней активности подряд.", "#F97316"),
    ("streak_days", 365, "Целый год!", "365 дней активности подряд.", "#F97316"),
    # Набрано очков
    ("points_earned", 50, "Первые очки", "Набрано 50 очков.", "#EAB308"),
    ("points_earned", 250, "Набираешь обороты", "Набрано 250 очков.", "#EAB308"),
    ("points_earned", 1000, "Тысячник", "Набрано 1000 очков.", "#EAB308"),
    ("points_earned", 5000, "Очковый магнат", "Набрано 5000 очков.", "#EAB308"),
    # Добавлено друзей
    ("friends_added", 1, "Не один", "Добавлен первый друг.", "#EC4899"),
    ("friends_added", 5, "Компания", "Добавлено 5 друзей.", "#EC4899"),
    ("friends_added", 10, "Душа компании", "Добавлено 10 друзей.", "#EC4899"),
    # Слова в квестах
    ("quest_words_completed", 1, "Первый квест", "Первое слово в квесте пройдено!", "#8B5CF6"),
    ("quest_words_completed", 10, "Охотник за квестами", "Пройдено 10 слов в квестах.", "#8B5CF6"),
    ("quest_words_completed", 50, "Квестовый мастер", "Пройдено 50 слов в квестах.", "#8B5CF6"),
]


def seed_achievements() -> None:
    db = SessionLocal()
    try:
        # The largest `order` already in use, so freshly-added entries are
        # appended after anything the admin already created or reordered,
        # never renumbering existing rows.
        max_order = db.query(func.max(Achievement.order)).scalar()
        next_order = (max_order + 1) if max_order is not None else 0
        created = 0
        for condition_type, condition_value, title, description, color in DEFAULT_ACHIEVEMENTS:
            exists = (
                db.query(Achievement.id)
                .filter(
                    Achievement.condition_type == condition_type,
                    Achievement.condition_value == condition_value,
                )
                .first()
            )
            if exists is not None:
                continue
            db.add(
                Achievement(
                    title=title,
                    description=description,
                    icon_key=None,
                    color=color,
                    condition_type=condition_type,
                    condition_value=condition_value,
                    enabled=True,
                    order=next_order,
                )
            )
            next_order += 1
            created += 1
        db.commit()
        print(f"[seed] created {created} achievements ({len(DEFAULT_ACHIEVEMENTS) - created} already existed)")
        from app.achievements.texts import apply_texts

        updated = apply_texts(db)
        db.commit()
        print(f"[seed] achievement slogans/translations updated: {updated}")
    finally:
        db.close()


def seed_mini_phrases() -> None:
    """The starter mini-phrases for every Russian dictionary -- only those
    whose words exist there (see app/mini_phrases/starter.py). Idempotent."""
    from app.mini_phrases.starter import fill_starter
    from app.models.dictionary import Dictionary

    db = SessionLocal()
    try:
        for dictionary in db.query(Dictionary).filter(Dictionary.language == "ru").all():
            report = fill_starter(db, dictionary)
            db.commit()
            print(
                f"[seed] mini-phrases for '{dictionary.name}': created {len(report['created'])}, "
                f"already {len(report['already'])}, skipped {len(report['skipped'])}, "
                f"forms added {len(report['forms_added'])}"
            )
            for item in report["skipped"]:
                print(f"[seed]   skipped «{item['text']}»: no word {', '.join(item['missing_words'])}")
    finally:
        db.close()


def seed_starter_500() -> None:
    """«Набор 500» (app/mini_phrases/starter_500.py) for every Russian
    dictionary, saved topic by topic -- one commit per topic, so a problem
    in one part never loses the rest or blocks the server start. Only
    phrases whose words exist are created; re-running adds what new words
    have unlocked and never duplicates."""
    from app.mini_phrases.starter import fill_phrases
    from app.mini_phrases.starter_500 import parse
    from app.models.dictionary import Dictionary

    phrases = parse()
    topics: dict[str, list[dict]] = {}
    for p in phrases:
        topics.setdefault(p["template"], []).append(p)
    db = SessionLocal()
    try:
        for dictionary in db.query(Dictionary).filter(Dictionary.language == "ru").all():
            created = already = skipped = 0
            missing: dict[str, int] = {}
            for topic, part in topics.items():
                try:
                    report = fill_phrases(db, dictionary, part)
                    db.commit()
                except Exception as e:  # noqa: BLE001 -- never block the server start
                    db.rollback()
                    print(f"[seed] «Набор 500» / {topic}: failed: {e}")
                    continue
                created += len(report["created"])
                already += len(report["already"])
                skipped += len(report["skipped"])
                for m in report["missing_words"]:
                    missing[m["word"]] = missing.get(m["word"], 0) + m["phrases"]
                print(f"[seed] «Набор 500» / {topic}: +{len(report['created'])}, waiting for words {len(report['skipped'])}")
            print(
                f"[seed] «Набор 500» for '{dictionary.name}': created {created}, already {already}, "
                f"waiting for words {skipped} of {len(phrases)}"
            )
            if missing:
                top = sorted(missing.items(), key=lambda kv: -kv[1])[:40]
                print("[seed]   missing words: " + ", ".join(f"{w} ({n})" for w, n in top))
    finally:
        db.close()


def clean_existing_icons() -> None:
    """Cleans icons uploaded before the cleanup existed (see
    app/core/icon_cleanup.py): seasons, ranks, achievements. A cleaned icon is
    saved as a new `...-clean.png` key, so each runs once; the old file is
    removed only after the new key is committed. One bad file never stops
    the rest or the server start."""
    from app.core.icon_cleanup import clean_icon
    from app.core.storage import MEDIA_ROOT, delete_by_key, save_bytes
    from app.models.achievement import Achievement
    from app.models.rating import Rank, Season

    db = SessionLocal()
    cleaned = 0
    try:
        for model in (Season, Rank, Achievement):
            for row in db.query(model).filter(model.icon_key.isnot(None)).all():
                key = row.icon_key
                if key.endswith("-clean.png"):
                    continue
                try:
                    path = MEDIA_ROOT / key
                    if not path.is_file():
                        continue
                    data = clean_icon(path.read_bytes())
                    if data is None:
                        continue
                    subdir = key.rsplit("/", 1)[0]
                    row.icon_key = save_bytes(data, subdir=subdir, filename_hint="icon.png", suffix="-clean.png")
                    db.commit()
                    delete_by_key(key)
                    cleaned += 1
                except Exception as e:  # noqa: BLE001 -- never block the server start
                    db.rollback()
                    print(f"[seed] icon cleanup failed for {key}: {e}")
        print(f"[seed] cleaned {cleaned} old icons (transparent background, trimmed)")
    finally:
        db.close()


if __name__ == "__main__":
    seed_admin()
    seed_ranks()
    seed_statuses()
    seed_achievements()
    seed_mini_phrases()
    seed_starter_500()
    clean_existing_icons()
