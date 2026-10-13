"""«Проверка текста»: one DeepSeek call that checks a Russian message the
user is about to send, and returns the breakdown the app renders directly.

Deliberately built exactly like the AI translator (app/translation/
deepseek.py): same API, same model, same JSON-only answer. THE KEY IS NOT
NEW AND NOT HARDCODED -- it is read from the one LearningSettings row that
Admin Web's «ИИ-перевод» section already manages (see `api_key` below), so
one key serves both features and the admin keeps ONE place to change it.

Language rule (the thing the original prototype did not spell out):
- `summary` and every `explanation` are written in the EXPLANATION language
  the user picked in the app (ru/tg/uz/en);
- `fragment`, `correct` and `corrected_text` are ALWAYS Russian -- they are
  pieces of the user's own Russian text and its corrected version, so the
  model is told explicitly never to translate them.

`ok` is computed here from the errors list, never taken from the model: an
answer that lists errors is never "all correct", whatever the model wrote.
"""

import json
import logging

import requests
from sqlalchemy.orm import Session

log = logging.getLogger(__name__)

API_URL = "https://api.deepseek.com/chat/completions"
MODEL = "deepseek-chat"
TIMEOUT = 90

# The six groups an error may belong to. The app draws its own localized
# title for each key (models/text_check.dart), so the model only ever sends
# the key -- never a translated group name.
ERROR_GROUPS = ("gender", "punctuation", "formality", "orthography", "grammar", "style")

# How the prompt names each explanation language. "tg" is GuYo's own Tajik
# code (the prototype's "tj" is not used anywhere in this project).
EXPLANATION_LANGUAGES = {
    "ru": "русский",
    "tg": "таджикский (тоҷикӣ)",
    "uz": "узбекский (oʻzbekcha, латиница)",
    "en": "English (английский)",
}

_GENDERS = {"male": "мужчина", "female": "женщина"}
_ADDRESSEES = {**_GENDERS, "unknown": "не выбран (не знаю)"}
_FORMALITY = {None: "не указана", "formal": "формально (Вы)", "informal": "неформально (ты)"}

SYSTEM_PROMPT = """Ты — строгий, но понятный преподаватель русского языка.
Твоя задача — проверить текст пользователя и вернуть разбор в СТРОГОМ JSON-формате.

КОНТЕКСТ (учитывай обязательно):
- Пол автора текста: {user_gender}
- Пол собеседника: {addressee_gender}
- Формальность: {formality}
- Проверять пунктуацию: {check_punctuation}
- Язык объяснений: {explanation_language}

ПРАВИЛА:
1. Проверяй всю грамматику: род, падежи, согласование, порядок слов, орфографию.
2. Род глаголов от первого лица должен соответствовать полу автора.
3. Формы обращения должны соответствовать полу собеседника. Если пол собеседника не выбран,
   не считай ошибкой ни одну из форм, но отметь в объяснении, если выбор формы зависит от него.
4. Если выбрана формальность — проверяй соответствие (ты/Вы, привет/здравствуйте, сорри/извините).
   Если формальность не выбрана — проверяй только отсутствие смешения стилей.
5. Пунктуацию проверяй ТОЛЬКО если проверять пунктуацию = true. Если знаков нет вообще — сообщи об этом.
6. Регистр (большая/маленькая буква) НЕ проверяй.
7. Орфографию и опечатки объединяй в одну группу "orthography".
8. Если ошибка подходит под две группы — покажи её в обеих.
9. Если всё правильно — верни пустой список ошибок и краткое пояснение, почему правильно.

ГРУППЫ ОШИБОК (используй ровно эти ключи, переводить их нельзя):
"gender" — род, "punctuation" — пунктуация, "formality" — формальность,
"orthography" — орфография, "grammar" — грамматика, "style" — стиль / естественность.

ЯЗЫК ОТВЕТА (очень важно):
- "summary" и "explanation" пиши НА ЯЗЫКЕ ОБЪЯСНЕНИЙ: {explanation_language}.
- "fragment", "correct" и "corrected_text" пиши ВСЕГДА ПО-РУССКИ — это фрагменты
  русского текста пользователя и его исправленный вариант. НЕ переводи их.

ФОРМАТ ОТВЕТА (строго JSON, без markdown, без пояснений вокруг):
{{
  "ok": true | false,
  "summary": "краткое пояснение (1–3 предложения)",
  "errors": [
    {{
      "group": "gender",
      "fragment": "сказала",
      "correct": "сказал",
      "explanation": "Вы указали, что вы мужчина, значит глагол должен быть в мужском роде."
    }}
  ],
  "corrected_text": "полный исправленный русский текст"
}}

Если ошибок нет:
{{
  "ok": true,
  "summary": "Всё правильно. Грамматика, род, формальность — в порядке.",
  "errors": [],
  "corrected_text": "исходный текст"
}}

Отвечай ТОЛЬКО JSON. Никакого текста до или после.
"""


class CheckUnavailable(RuntimeError):
    """DeepSeek could not answer at all -- a rejected key, no balance, a
    network failure, or an answer that isn't the JSON we asked for. The
    technical reason is logged; the user is told one calm sentence (see
    app/routers/text_check.py)."""


def _clean(value: object, limit: int) -> str:
    return str(value or "").strip()[:limit]


def _prompt(
    text: str,
    user_gender: str,
    addressee_gender: str,
    formality: str | None,
    check_punctuation: bool,
    explanation_language: str,
) -> str:
    context = SYSTEM_PROMPT.format(
        user_gender=_GENDERS.get(user_gender, user_gender),
        addressee_gender=_ADDRESSEES.get(addressee_gender, addressee_gender),
        formality=_FORMALITY.get(formality, formality or "не указана"),
        check_punctuation="да" if check_punctuation else "нет",
        explanation_language=EXPLANATION_LANGUAGES.get(explanation_language, explanation_language),
    )
    return f"{context}\n\nТЕКСТ ПОЛЬЗОВАТЕЛЯ:\n{text}"


def _normalize(raw: dict, original_text: str) -> dict:
    """The model's JSON in the exact shape the app renders -- unknown groups
    fall back to "grammar", empty entries are dropped, and `ok` is decided
    here rather than trusted from the answer."""
    errors: list[dict] = []
    for item in raw.get("errors") or []:
        if not isinstance(item, dict):
            continue
        fragment = _clean(item.get("fragment"), 300)
        correct = _clean(item.get("correct"), 300)
        if not fragment and not correct:
            continue
        group = _clean(item.get("group"), 32).lower()
        errors.append(
            {
                "group": group if group in ERROR_GROUPS else "grammar",
                "fragment": fragment,
                "correct": correct,
                "explanation": _clean(item.get("explanation"), 1000),
            }
        )
    return {
        "ok": not errors,
        "summary": _clean(raw.get("summary"), 1000),
        "errors": errors,
        "corrected_text": _clean(raw.get("corrected_text"), 4000) or original_text,
    }


def check_text(
    api_key: str,
    text: str,
    user_gender: str,
    addressee_gender: str,
    formality: str | None,
    check_punctuation: bool,
    explanation_language: str,
) -> dict:
    """One check. Raises [CheckUnavailable] for anything that isn't a usable
    answer; returns the normalized result otherwise."""
    payload = {
        "model": MODEL,
        "temperature": 0.2,
        "response_format": {"type": "json_object"},
        "messages": [
            {
                "role": "user",
                "content": _prompt(
                    text, user_gender, addressee_gender, formality, check_punctuation, explanation_language
                ),
            }
        ],
    }
    try:
        response = requests.post(
            API_URL,
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
            json=payload,
            timeout=TIMEOUT,
        )
    except requests.RequestException as e:
        raise CheckUnavailable(f"DeepSeek недоступен: {e}") from e

    if response.status_code == 401:
        raise CheckUnavailable("DeepSeek отклонил ключ (401)")
    if response.status_code == 402:
        raise CheckUnavailable("На счёте DeepSeek закончились деньги (402)")
    if response.status_code != 200:
        raise CheckUnavailable(f"DeepSeek вернул {response.status_code}: {response.text[:300]}")

    try:
        content = response.json()["choices"][0]["message"]["content"]
        raw = json.loads(content)
    except (ValueError, KeyError, IndexError, TypeError) as e:
        raise CheckUnavailable(f"Неожиданный ответ DeepSeek: {e}") from e
    if not isinstance(raw, dict):
        raise CheckUnavailable("Ответ DeepSeek не является JSON-объектом")

    log.info(
        "text check: %s chars, user=%s addressee=%s formality=%s punctuation=%s lang=%s -> %s error(s)",
        len(text),
        user_gender,
        addressee_gender,
        formality,
        check_punctuation,
        explanation_language,
        len(raw.get("errors") or []),
    )
    return _normalize(raw, text)


def api_key(db: Session) -> str:
    """The DeepSeek key, from the SAME settings row Admin Web's «ИИ-перевод»
    section writes (LearningSettings.deepseek_api_key) -- the one key this
    project already uses for AI translation. Imported locally so this module
    stays independent of the translator's own code."""
    from app.translation.deepseek import settings_row

    return (settings_row(db).deepseek_api_key or "").strip()
