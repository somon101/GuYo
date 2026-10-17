"""Перевод интерфейса приложения на новый язык — по строкам из mobile/lib/l10n.

Ключи словаря — сами русские тексты, поэтому переводить нужно только значения.
Скрипт читает ключи из `strings.dart` (единственный источник правды), просит
модель перевести их партиями и пишет готовый Dart-словарь в `strings_zh.dart`
(или другой язык). После этого язык надо добавить в `uiLanguages` в l10n.dart и
собрать приложение — иначе строк в сборке не будет.

Зачем отдельный модуль: добавление языка интерфейса не должно превращаться в
ручную работу на 600 строк, а перевод — в правку кода.

Запуск:
    python -m app.ui_translate zh "Китайский" ../mobile/lib/l10n/strings_zh.dart
"""

import json
import re
import sys
from pathlib import Path

from app.database import SessionLocal
from app.mini_phrases.generate import chat

BATCH = 40

_SYSTEM = (
    "You translate an app's interface strings. Input: {\"to\":\"target language\","
    "\"s\":[{\"k\":\"source string\"}]}. Translate every string into the target language. "
    "Rules: keep placeholders EXACTLY as written ({0}, {1}, {name} -- braces and text unchanged), keep the "
    "punctuation style and capitalisation of the source, do not add explanations, do not merge or split "
    "strings, keep words like GuYo or Google as they are. UI strings are short: prefer the shortest natural "
    "wording. Reply JSON only: {\"r\":[{\"k\":\"source string exactly as given\",\"t\":\"translation\"}]}."
)


def keys_from_dart(path: Path) -> list[str]:
    """Ключи словаря: `'текст': ('tg', 'uz'),` в strings.dart."""
    src = path.read_text(encoding="utf-8")
    return re.findall(r"^\s*'((?:[^'\\]|\\.)+)'\s*:", src, re.M)


def _dart_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n")


def translate(keys: list[str], language_name: str, cache: dict[str, str]) -> tuple[dict[str, str], int]:
    """Переводит недостающие ключи. Уже переведённое берётся из кэша.

    Кэш пишется после каждой партии: длинный перевод рвётся на середине
    (сеть, лимит сервиса), и повтор не должен заново платить за готовое.
    """
    db = SessionLocal()
    result = dict(cache)
    tokens = 0
    pending = [key for key in keys if key not in result]
    try:
        for start in range(0, len(pending), BATCH):
            chunk = pending[start : start + BATCH]
            data = None
            for attempt in range(2):
                try:
                    data, used = chat(
                        db,
                        _SYSTEM,
                        {"to": language_name, "s": [{"k": key} for key in chunk]},
                        max_tokens=120 * len(chunk) + 400,
                    )
                    tokens += used
                    break
                except Exception as error:  # сеть, лимит, таймаут сервиса
                    print(f"  партия не прошла (попытка {attempt + 1}): {type(error).__name__}")
            if not data:
                print("  партия пропущена, останется без перевода")
                continue
            for row in data.get("r") or []:
                if not isinstance(row, dict):
                    continue
                key = str(row.get("k") or "")
                value = str(row.get("t") or "").strip()
                if key and value:
                    result[key] = value
            done = min(start + BATCH, len(pending))
            print(f"  переведено {done} из {len(pending)} (всего в словаре {len(result)})")
    finally:
        db.close()
    return result, tokens


def write_dart(path: Path, values: dict[str, str], language_name: str) -> int:
    lines = [
        f"/// Интерфейс на языке «{language_name}», ключ — русский текст (см. l10n.dart).",
        "///",
        "/// Файл создан `python -m app.ui_translate` и правится вручную только при",
        "/// необходимости: перевод идёт из strings.dart, а не из этого файла.",
        "const Map<String, String> zhStrings = {",
    ]
    for key, value in values.items():
        lines.append(f"  '{_dart_escape(key)}': '{_dart_escape(value)}',")
    lines.append("};")
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")
    return len(values)


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print('Использование: python -m app.ui_translate <код> "<Название>" <путь к strings_xx.dart>')
        return 2
    code, language_name = argv[1], argv[2]
    out = Path(argv[3]) if len(argv) > 3 else Path(f"../mobile/lib/l10n/strings_{code}.dart")
    source = Path(__file__).resolve().parents[2] / "mobile" / "lib" / "l10n" / "strings.dart"
    if not source.exists():
        print(f"Не найден словарь ключей: {source}")
        return 2
    keys = keys_from_dart(source)
    print(f"[ui-translate] ключей: {len(keys)}, язык: {language_name}")
    cache_path = out.with_suffix(out.suffix + ".json")
    cache: dict[str, str] = {}
    if cache_path.exists():
        try:
            cache = json.loads(cache_path.read_text(encoding="utf-8"))
            print(f"[ui-translate] из кэша уже готово: {len(cache)}")
        except json.JSONDecodeError:
            cache = {}
    values, tokens = translate(keys, language_name, cache)
    cache_path.write_text(json.dumps(values, ensure_ascii=False, indent=1), encoding="utf-8")
    written = write_dart(out, values, language_name)
    print(f"[ui-translate] записано {written} строк в {out} · токенов {tokens}")
    missing = [key for key in keys if key not in values]
    if missing:
        print(f"[ui-translate] без перевода осталось {len(missing)}:")
        for key in missing[:10]:
            print("   " + json.dumps(key, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
