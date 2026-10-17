"""AI-assisted mini-phrase generation, with the script doing everything it can
so as few tokens as possible go to the model.

What the SCRIPT does (no tokens):
- analysis: how many mini-phrases the current words allow, and which missing
  words would unlock the most (phrases of «Мои фразы» short of a word, and
  key words for mini-phrases);
- roles: guesses a missing word role from the word itself;
- the word list for the model: the chosen topic's words plus anchor words
  (pronouns, the most important verbs), as compact `id:word` -- no
  translations or forms, so few tokens;
- checking every phrase the model returns (words from the list only, 2-5,
  not a duplicate, has Tajik, usefulness >= 4), the similarity to what
  exists, choosing/creating templates, adding missing word forms on save.

What the MODEL does: invents sensible everyday phrases from that list (picking
the words itself, so they mean something), puts the words into the right
forms, rates usefulness, says where it's said and translates (tg/uz/en);
rebuilds a phrase that came out too similar; builds full word cards
(translations + all forms) for new words.
Nothing is saved until the admin picks what to keep.
"""

import json
import re

import requests
from fastapi import HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

# Язык, на котором написана сама мини-фраза. Переводы делаются на все
# остальные включённые языки.
PHRASE_LANGUAGE = "ru"


def translation_languages() -> list[tuple[str, str]]:
    """Языки, на которые переводим мини-фразы: все включённые, кроме самого
    языка фразы.

    Список берётся из таблицы languages, поэтому язык, добавленный в админке,
    попадает в генерацию сам -- без правки кода. Раньше здесь были зашиты три
    кода (tg/uz/en), и четвёртый язык просто не переводился.
    """
    from app.core.languages_in_db import known_codes
    from app.database import SessionLocal
    from app.models.language import Language

    db = SessionLocal()
    try:
        rows = (
            db.query(Language.code, Language.name)
            .filter(Language.is_enabled.is_(True))
            .order_by(Language.sort_order, Language.code)
            .all()
        )
    finally:
        db.close()
    known = known_codes()
    pairs = [(code, name) for code, name in rows if code != PHRASE_LANGUAGE]
    if known:
        pairs = [(code, name) for code, name in pairs if code in known]
    return pairs or [("tg", "Таджикский"), ("uz", "Узбекский"), ("en", "Английский")]


def _langs_payload(langs: list[tuple[str, str]]) -> str:
    """`tg:Таджикский,uz:Узбекский` -- модель видит и код, и название языка."""
    return ",".join(f"{code}:{name}" for code, name in langs)

from app.core.content_language import primary_translation
from app.mini_phrases.service import normalize_answer
from app.models.category import Category
from app.models.concept import WordEntry
from app.models.dictionary import Dictionary
from app.models.mini_phrase import (
    WORD_ROLES,
    MiniPhrase,
    MiniPhrasePart,
    MiniPhraseTemplate,
    MiniPhraseTranslation,
)
from app.models.phrase import Phrase
from app.models.word import Word, WordForm, WordTranslation

API_URL = "https://api.deepseek.com/chat/completions"
MODEL = "deepseek-chat"
SIMILAR_THRESHOLD = 60

PRONOUNS = {"я", "ты", "он", "она", "оно", "мы", "вы", "они"}

# Role patterns a skeleton can follow (2–4 words).
PATTERNS: list[tuple[str, ...]] = [
    ("pronoun", "verb"),
    ("noun", "verb"),
    ("pronoun", "verb", "noun"),
    ("noun", "adjective"),
    ("pronoun", "verb", "adverb"),
    ("noun", "verb", "noun"),
    ("pronoun", "verb", "adjective", "noun"),
]

# Key words for mini-phrases, suggested when the dictionary lacks them.
KEY_WORDS: dict[str, str] = {
    **{p: "pronoun" for p in ("я", "ты", "он", "она", "мы", "вы", "они")},
    **{v: "verb" for v in ("идти", "есть", "пить", "спать", "работать", "читать", "писать", "говорить",
                           "знать", "понимать", "жить", "любить", "хотеть", "видеть", "ждать", "делать",
                           "смотреть", "слушать", "играть", "учиться")},
    **{n: "noun" for n in ("вода", "чай", "хлеб", "дом", "книга", "мама", "папа", "друг", "работа", "школа")},
    **{a: "adjective" for a in ("большой", "маленький", "хороший", "новый")},
}

ROLE_LABELS = {
    "ru": {"pronoun": "кто", "verb": "действие", "noun": "что", "adjective": "какой", "adverb": "как",
           "preposition": "предлог", "number": "сколько", "other": "слово"},
    "tg": {"pronoun": "кӣ", "verb": "амал", "noun": "чӣ", "adjective": "чӣ гуна", "adverb": "чӣ тавр",
           "preposition": "пешоянд", "number": "чанд", "other": "калима"},
    "uz": {"pronoun": "kim", "verb": "harakat", "noun": "nima", "adjective": "qanday", "adverb": "qanday qilib",
           "preposition": "koʻmakchi", "number": "nechta", "other": "soʻz"},
}

_TOKEN = re.compile(r"[^\W\d_]+", re.UNICODE)


# --- Roles & words ------------------------------------------------------------


def guess_role(text: str) -> str:
    w = text.strip().lower()
    if w in PRONOUNS:
        return "pronoun"
    if w.endswith(("ться", "тись", "чься", "ть", "чь", "ти")):
        return "verb"
    if w.endswith(("ый", "ий", "ой", "ая", "яя", "ое", "ее")):
        return "adjective"
    return "noun"


def role_of(word: Word, role: str | None = None) -> str:
    """Роль слова: сначала языковая запись (переданная сюда), потом понятие,
    потом догадка по написанию."""
    return role or word.role or guess_role(word.word)


def _roles_for(db: Session, words: list[Word], language: str) -> dict[int, str]:
    """Роль каждого слова В ЯЗЫКЕ, на котором собираем фразы.

    Роль -- свойство языка: понятие может быть глаголом в одном языке и
    существительным в другом. Поэтому берём её из языковой записи, а значение с
    понятия остаётся запасным."""
    from app.word_entries import role_for

    return {w.id: role_of(w, role_for(db, w, language)) for w in words}


def _words(db: Session, dictionary_id: int) -> list[Word]:
    return db.query(Word).filter(Word.dictionary_id == dictionary_id).order_by(Word.id).all()


def _known_tokens(words: list[Word], language: str) -> set[str]:
    tokens: set[str] = set()
    for w in words:
        tokens.add(w.word.strip().lower())
        for f in w.forms:
            if f.language == language:
                tokens.add(f.text.strip().lower())
    return tokens


def _used_combos(db: Session, dictionary_id: int) -> set[frozenset]:
    combos: dict[int, set[int]] = {}
    rows = (
        db.query(MiniPhrasePart.mini_phrase_id, MiniPhrasePart.word_id)
        .join(MiniPhrase, MiniPhrase.id == MiniPhrasePart.mini_phrase_id)
        .filter(MiniPhrase.dictionary_id == dictionary_id)
        .all()
    )
    for mp_id, word_id in rows:
        combos.setdefault(mp_id, set()).add(word_id)
    return {frozenset(v) for v in combos.values()}


# --- Analysis (script only) -----------------------------------------------------


def analyze(db: Session, dictionary: Dictionary) -> dict:
    words = _words(db, dictionary.id)
    by_role: dict[str, int] = {}
    for w in words:
        by_role[role_of(w)] = by_role.get(role_of(w), 0) + 1

    def combos_for(counts: dict[str, int]) -> int:
        total = 0
        for pattern in PATTERNS:
            n = 1
            for r in pattern:
                n *= counts.get(r, 0)
            total += n
        return total

    possible = combos_for(by_role)
    existing = db.query(func.count(MiniPhrase.id)).filter(MiniPhrase.dictionary_id == dictionary.id).scalar() or 0
    known = _known_tokens(words, dictionary.language)

    # Words that «Мои фразы» phrases are missing.
    missing_by_phrase: list[set[str]] = []
    for p in db.query(Phrase).filter(Phrase.dictionary_id == dictionary.id).all():
        missing = {t.lower() for t in _TOKEN.findall(p.original)} - known
        if missing:
            missing_by_phrase.append(missing)
    suggestions: dict[str, dict] = {}
    for missing in missing_by_phrase:
        for token in missing:
            s = suggestions.setdefault(token, {"text": token, "source": "phrases", "unlocks": 0, "appears": 0})
            s["appears"] += 1
            if len(missing) == 1:
                s["unlocks"] += 1

    # Key words for mini-phrases.
    for text, role in KEY_WORDS.items():
        if text in known or text in suggestions:
            continue
        with_it = dict(by_role)
        with_it[role] = with_it.get(role, 0) + 1
        gain = combos_for(with_it) - possible
        if gain > 0:
            suggestions[text] = {"text": text, "source": "key", "unlocks": gain, "appears": 0, "role": role}

    ranked = sorted(
        suggestions.values(),
        key=lambda s: (s["source"] != "phrases" or s["unlocks"] == 0, -s["unlocks"], -s["appears"], s["text"]),
    )
    return {
        "words": len(words),
        "roles": by_role,
        "existing_mini_phrases": existing,
        "possible_combinations": possible,
        "phrases_short_of_words": len(missing_by_phrase),
        "missing_words": ranked[:60],
    }


# --- The model ------------------------------------------------------------------


def _api_key(db: Session) -> str:
    from app.translation.deepseek import settings_row

    key = settings_row(db).deepseek_api_key
    if not key:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Не задан ключ DeepSeek — добавьте его в «ИИ-инструменты» → «Перевод»",
        )
    return key


def chat(db: Session, system: str, payload: dict, max_tokens: int) -> tuple[dict, int]:
    """One JSON-mode request. Returns (parsed JSON, tokens used)."""
    try:
        response = requests.post(
            API_URL,
            headers={"Authorization": f"Bearer {_api_key(db)}"},
            json={
                "model": MODEL,
                "temperature": 0.4,
                "max_tokens": max_tokens,
                "response_format": {"type": "json_object"},
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": json.dumps(payload, ensure_ascii=False, separators=(",", ":"))},
                ],
            },
            timeout=150,
        )
    except requests.RequestException:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="DeepSeek не отвечает, попробуйте ещё раз")
    if response.status_code == 401:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="DeepSeek отклонил ключ (401)")
    if response.status_code == 402:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="На счёте DeepSeek закончились деньги (402)")
    if response.status_code >= 400:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=f"Ошибка DeepSeek ({response.status_code})")
    body = response.json()
    try:
        data = json.loads(body["choices"][0]["message"]["content"])
    except (KeyError, ValueError, TypeError):
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="DeepSeek вернул непонятный ответ, попробуйте ещё раз")
    return data, int((body.get("usage") or {}).get("total_tokens") or 0)


MIN_USEFULNESS = 4
# A content word (noun, verb, adjective, adverb) may appear in at most this many mini-phrases.
WORD_USE_CAP = 10

_PHRASE_SYSTEM = (
    "You are an experienced Russian teacher. Your learners are adult beginners (native Tajik or Uzbek) who need "
    "Russian to COMMUNICATE. Input: {\"n\":how many,\"topic\":\"topic or empty\",\"w\":\"id:word,...\" (the "
    "learner's dictionary — the ONLY words you may use),\"have\":[mini-phrases the learner ALREADY has]}. "
    "Take your time and think deeply: draft more phrases than needed, reread each one several times as a "
    "native speaker would, and keep only the best. "
    "Step 1 — study w completely: which words exist, what they let you say, what is missing. "
    "Step 2 — write n phrases of 2-5 words that a person really says in conversation in any area of life (meeting "
    "people, family, work, study, shop, transport, doctor, city, phone, time, home): questions, requests, answers, "
    "politeness, needs, wishes, plans, feelings, opinions. Use as many words as the thought needs: two only if the "
    "phrase is complete and natural («Я понял», «Можно войти?»), otherwise 3-5. Good: «Я не понимаю», «Где ты "
    "живёшь?», «Мне нужна помощь», «Я хочу работать здесь», «Сколько это стоит?». Bad: descriptive scenes («Я вижу "
    "собаку», «Я пью чай»), absurd combinations, ungrammatical Russian. "
    "Step 3 — check every phrase before answering, drop and replace the ones that fail: (a) it is 100% correct, "
    "natural Russian with the right case/person/gender (never «Я помню ты» — must be «Я помню тебя»); (b) EVERY word "
    "in its exact written form belongs to the w word whose id you give (a form of THAT word: «тебя» is a form of "
    "«ты», never of another word; if the form or the word is not in w, do not use the phrase — put the word in "
    "need); (c) its MEANING differs from every phrase in have and from your other phrases (not the same thought with "
    "another pronoun or object); (d) no content word (noun, verb, adjective) is used in more than one of your phrases "
    "— cover many different words and situations. "
    "Rate u = how often a beginner needs it in real conversation, 1-5. "
    "ALWAYS list in need 5-10 words NOT in w that would most widen what the learner can say, each with an example "
    "phrase. "
    "Translate every phrase into EVERY language listed in langs (input, form \"code:name,...\"): put the natural "
    "translation of t into tr, keyed by the language code, nothing else there. "
    "Reply JSON only: {\"r\":[{\"t\":\"the full correct phrase\",\"p\":[[id,\"word exactly as in t\"],...],"
    "\"u\":5,\"s\":\"situation, 2-4 Russian words\",\"tr\":{\"<code from langs>\":\"translation\"}}],"
    "\"need\":[{\"w\":\"word (base form)\",\"ex\":\"example phrase\"}]}. "
    "p lists every word of t in order."
)


def _word_use(db: Session, dictionary_id: int) -> dict[int, int]:
    return dict(
        db.query(MiniPhrasePart.word_id, func.count(func.distinct(MiniPhrasePart.mini_phrase_id)))
        .join(MiniPhrase, MiniPhrase.id == MiniPhrasePart.mini_phrase_id)
        .filter(MiniPhrase.dictionary_id == dictionary_id)
        .group_by(MiniPhrasePart.word_id)
        .all()
    )


def word_list(db: Session, dictionary: Dictionary, category_id: int | None, limit: int = 260) -> list[Word]:
    """The words sent to the model: the chosen topic's words (or all) plus the
    anchor words every phrase leans on -- pronouns and the most important
    verbs -- in a compact `id:word` form. Content words already in
    WORD_USE_CAP mini-phrases are left out, and the least used come first,
    so hundreds of phrases spread over the whole dictionary."""
    words = _words(db, dictionary.id)
    use = _word_use(db, dictionary.id)
    roles = _roles_for(db, words, phrase_language(dictionary))
    fresh = [w for w in words if roles[w.id] == "pronoun" or use.get(w.id, 0) < WORD_USE_CAP]
    anchors = [w for w in fresh if roles[w.id] == "pronoun"]
    anchors += sorted((w for w in fresh if roles[w.id] == "verb"), key=lambda w: (use.get(w.id, 0) // 3, -w.importance))[:40]
    topic = [w for w in fresh if category_id is None or w.category_id == category_id]
    topic.sort(key=lambda w: (use.get(w.id, 0) // 3, -w.importance))
    picked = {w.id: w for w in anchors}
    for w in topic:
        if len(picked) >= limit:
            break
        picked.setdefault(w.id, w)
    return list(picked.values())


def _compact(words: list[Word]) -> str:
    return ",".join(f"{w.id}:{w.word.strip().lower()}" for w in words)


def phrase_language(dictionary: Dictionary) -> str:
    """Язык, на котором собираются мини-фразы: тот, что человек изучает.

    Пока фразы пишутся на языке словаря (по-русски), но выбор уже идёт через
    изучаемый язык: когда появятся фразы других языков, они возьмут роли и
    порядок частей из своего языка, а не из русского.
    """
    from app.core.content_language import learning_language

    return learning_language() or dictionary.language or PHRASE_LANGUAGE


def ai_phrases(
    db: Session,
    words: list[Word],
    count: int,
    topic: str,
    avoid: list[str],
    langs: list[tuple[str, str]] | None = None,
) -> tuple[list[dict], list[dict], int]:
    langs = langs or translation_languages()
    results: list[dict] = []
    needs: dict[str, dict] = {}
    tokens = 0
    remaining = count
    seen = list(avoid)
    while remaining > 0:
        n = min(25, remaining)
        data, used = chat(
            db,
            _PHRASE_SYSTEM,
            {"n": n, "topic": topic, "w": _compact(words), "have": seen[-150:], "langs": _langs_payload(langs)},
            # Каждый язык добавляет текст перевода, поэтому бюджет растёт с их
            # числом: иначе на пяти языках ответ обрезался бы на середине.
            max_tokens=(190 + 50 * len(langs)) * n + 700,
        )
        tokens += used
        got = [i for i in data.get("r") or [] if isinstance(i, dict)]
        results += got
        seen += [str(i.get("t") or " ".join(str(x[1]) for x in i.get("p") or [] if isinstance(x, (list, tuple)) and len(x) == 2)) for i in got]
        for need in data.get("need") or []:
            if isinstance(need, dict) and str(need.get("w") or "").strip():
                key = str(need["w"]).strip().lower()[:60]
                needs.setdefault(key, {"text": key, "example": str(need.get("ex") or "").strip()[:120]})
        remaining -= n
    return results, list(needs.values()), tokens


# --- Checking a candidate (script only) ------------------------------------------


def _template_name(roles: list[str]) -> str:
    if len(roles) == 2 and roles[1] == "adjective" and roles[0] in ("noun", "pronoun"):
        return "Кто/что + какой"
    labels = []
    for i, r in enumerate(roles):
        if i == 0 and r in ("pronoun", "noun"):
            labels.append("кто")
        else:
            labels.append(ROLE_LABELS["ru"].get(r, "слово"))
    return " + ".join(labels).capitalize()


def _template_texts(roles: list[str]) -> dict:
    def build(lang: str, intro: str, outro: str) -> str:
        bits = []
        for i, r in enumerate(roles, start=1):
            label = ROLE_LABELS[lang].get(r, ROLE_LABELS[lang]["other"])
            bits.append(f"{label} — {{{i}}} ({{{i}.tr}})")
        return f"{intro}{', '.join(bits)}. {outro}{{phrase}}"

    return {
        "explanation_ru": build("ru", "Чтобы сказать «{translation}», соберите по порядку: ", "Получается: "),
        "explanation_tg": build("tg", "Барои гуфтани «{translation}» бо тартиб ҷамъ кунед: ", "Натиҷа: "),
        "explanation_uz": build("uz", "«{translation}» deyish uchun tartib bilan yigʻing: ", "Natija: "),
    }


# Words that carry no meaning of their own for similarity: two phrases are
# not "the same" just because both start with «я» or contain «не».
_FUNCTION_WORDS = {
    "я", "ты", "он", "она", "оно", "мы", "вы", "они", "меня", "тебя", "его", "её", "ее", "нас", "вас", "их",
    "мне", "тебе", "ему", "ей", "нам", "вам", "им", "мой", "моя", "моё", "мое", "мои", "твой", "твоя", "твои",
    "не", "и", "а", "но", "в", "во", "на", "с", "со", "у", "к", "ко", "по", "о", "об", "от", "до", "из", "за",
    "для", "это", "то", "да", "нет", "ли", "же", "бы", "уже", "очень", "тоже", "там", "тут", "здесь",
}


_PRONOUNS = {"я", "ты", "он", "она", "оно", "мы", "вы", "они", "меня", "тебя", "его", "её", "ее", "нас", "вас", "их",
             "мне", "тебе", "ему", "ей", "нам", "вам", "им"}


_PRONOUN_CASES = {
    "я": {"меня", "мне", "мной", "мною"},
    "ты": {"тебя", "тебе", "тобой", "тобою"},
    "он": {"его", "него", "ему", "нему", "им", "ним", "нем"},
    "она": {"ее", "нее", "ей", "ней", "ею", "нею"},
    "оно": {"его", "него", "ему", "нему", "им", "ним", "нем"},
    "мы": {"нас", "нам", "нами"},
    "вы": {"вас", "вам", "вами"},
    "они": {"их", "них", "им", "ним", "ими", "ними"},
    "мой": {"моя", "мое", "мои", "моего", "моей", "моему", "моих", "моим", "моими", "моем", "мою"},
    "твой": {"твоя", "твое", "твои", "твоего", "твоей", "твоему", "твоих", "твоим", "твоими", "твоем", "твою"},
}


def _plausible_form(word: Word, text: str) -> bool:
    """A new form must look like a form of THIS word: a pronoun only its
    real cases («ты → тебя», never «мы → я»), and any other
    form starts with the same letter as the word («пить → пью», «идти → иду»),
    so «я» is never taken as a form of «мы»."""
    base = word.word.strip().lower().replace("ё", "е")
    t = text.lower().replace("ё", "е")
    if role_of(word) == "pronoun" or base in _PRONOUN_CASES:
        return t in _PRONOUN_CASES.get(base, set())
    return bool(base) and bool(t) and base[0] == t[0]


def _stem(token: str) -> str:
    t = token.lower().replace("ё", "е")
    return t[:5] if len(t) > 5 else t


def _similarity(db: Session, dictionary_id: int):
    """A cold, script-only check -- the model never sees it. Two phrases are
    similar when they share their MEANING words: function words (pronouns,
    prepositions, «не»…) are ignored, and every form of one dictionary word
    counts as that word («пью» = «пьём»). Score = shared / all meaning words,
    so «Я пью чай» vs «Мы пьём чай» = 100%, «Я хочу чай» vs «Я пью чай» = 33%,
    «Я иду домой» vs «Я пью чай» = 0%. Compared with existing mini-phrases,
    «Мои фразы» and the rest of the batch."""
    words = {w.id: w for w in _words(db, dictionary_id)}

    def ids_key(ids: set[int]) -> set[str]:
        out = set()
        for wid in ids:
            w = words.get(wid)
            if w is None:
                continue
            if role_of(w) != "pronoun" and (role_of(w) == "preposition" or w.word.strip().lower() in _FUNCTION_WORDS):
                continue
            out.add(f"w{wid}")
        return out

    def text_key(text: str) -> set[str]:
        return {_stem(t) for t in _TOKEN.findall(text.lower()) if t not in _FUNCTION_WORDS or t in _PRONOUNS}

    def stems_of_ids(ids: set[int]) -> set[str]:
        return {_stem(words[i].word.strip()) for i in ids if i in words and f"w{i}" in ids_key({i})}

    existing: list[tuple[str, set[int] | None, str]] = []
    parts: dict[int, set[int]] = {}
    texts: dict[int, str] = {}
    for mp_id, text, word_id in (
        db.query(MiniPhrase.id, MiniPhrase.text, MiniPhrasePart.word_id)
        .join(MiniPhrasePart, MiniPhrasePart.mini_phrase_id == MiniPhrase.id)
        .filter(MiniPhrase.dictionary_id == dictionary_id)
        .all()
    ):
        parts.setdefault(mp_id, set()).add(word_id)
        texts[mp_id] = text
    for mp_id, ids in parts.items():
        existing.append((texts[mp_id], ids, "mini"))
    for (original,) in db.query(Phrase.original).filter(Phrase.dictionary_id == dictionary_id).all():
        existing.append((original, None, "phrase"))

    def score(text: str, word_ids: set[int], batch: list[tuple[str, set[int]]]):
        a_ids = ids_key(word_ids)
        a_text = text_key(text) | stems_of_ids(word_ids)
        best = (0, None, None)
        for other_text, other_ids, source in existing + [(t, i, "batch") for t, i in batch]:
            if normalize_answer(other_text) == normalize_answer(text):
                value = 100
            elif other_ids is not None:
                b = ids_key(other_ids)
                value = round(100 * len(a_ids & b) / len(a_ids | b)) if (a_ids or b) else 0
            else:
                b = text_key(other_text)
                value = round(100 * len(a_text & b) / len(a_text | b)) if (a_text and b) else 0
            if value > best[0]:
                best = (value, other_text, source)
        return best

    return score


def _normalize_parts(item: dict, by_text: dict) -> list:
    """The model's parts in whatever shape it sent them -- [[id, "word"]],
    ids as strings, {"id":..,"w":..} objects -- as [[int id, "word"]]. When
    they are missing or unusable but the full phrase `t` is there, the script
    splits `t` itself and finds every token in the dictionary."""
    out = []
    for p in item.get("p") or []:
        wid, text = None, None
        if isinstance(p, (list, tuple)) and len(p) == 2:
            wid, text = p
        elif isinstance(p, dict):
            wid = p.get("id", p.get("i"))
            text = p.get("w", p.get("t", p.get("text")))
        if isinstance(text, int) and not isinstance(wid, int):
            wid, text = text, wid  # [["word", id]]
        if isinstance(wid, str) and wid.strip().isdigit():
            wid = int(wid.strip())
        out.append([wid, text])
    tokens = _TOKEN.findall(str(item.get("t") or ""))
    usable = out and all(isinstance(w, int) and t for w, t in out)
    if not usable and tokens:
        guessed = [[by_text[t.lower()].id if t.lower() in by_text else None, t] for t in tokens]
        if all(w is not None for w, _ in guessed):
            return guessed
    return out


def check_candidates(db: Session, dictionary: Dictionary, raw: list[dict], allowed_ids: set[int] | None = None) -> list[dict]:
    """Turns the model's (or the admin's) items into checked preview items."""
    words = {w.id: w for w in _words(db, dictionary.id)}
    existing_texts = {normalize_answer(t) for (t,) in db.query(MiniPhrase.text).filter(MiniPhrase.dictionary_id == dictionary.id)}
    templates = {t.name: t for t in db.query(MiniPhraseTemplate).all()}
    score = _similarity(db, dictionary.id)
    batch: list[tuple[str, set[int]]] = []
    by_text: dict[str, Word] = {}
    for w in words.values():
        for t in [w.word] + [f.text for f in w.forms if f.language == dictionary.language]:
            by_text.setdefault(t.strip().lower(), w)
    content_use: dict[int, int] = {}
    # How many saved mini-phrases each word is already in: across hundreds of
    # phrases no word should dominate («чай, чай, чай»).
    saved_use = dict(
        db.query(MiniPhrasePart.word_id, func.count(func.distinct(MiniPhrasePart.mini_phrase_id)))
        .join(MiniPhrase, MiniPhrase.id == MiniPhrasePart.mini_phrase_id)
        .filter(MiniPhrase.dictionary_id == dictionary.id)
        .group_by(MiniPhrasePart.word_id)
        .all()
    )
    out = []
    for item in raw:
        reason = None
        if item.get("ok") is False:
            reason = "ИИ: из этих слов не получается естественная фраза"
        parts_in = _normalize_parts(item, by_text)
        parts = []
        broken = False
        for p in parts_in:
            if not isinstance(p, (list, tuple)) or len(p) != 2:
                reason = reason or "Неверный формат частей"
                broken = True
                continue
            wid, text = p
            word = words.get(wid) if isinstance(wid, int) else None
            text = str(text).strip()
            if word is None or not text:
                reason = reason or f"Слова «{text or wid}» нет в словаре"
                broken = True
                continue
            known = {word.word.strip().lower()} | {
                f.text.strip().lower() for f in word.forms if f.language == dictionary.language
            }
            if text.lower() not in known and text.lower() in by_text:
                # The model gave the wrong id: the text is another word (or its form).
                word = by_text[text.lower()]
                known = {text.lower()}
            if text.lower() not in known and not _plausible_form(word, text):
                reason = reason or f"«{text}» не похоже на форму слова «{word.word}»"
            primary = primary_translation(word)
            parts.append(
                {
                    "text": text,
                    "word_id": word.id,
                    "word": word.word,
                    "role": role_of(word),
                    "new_form": text.lower() not in known,
                    "word_translation": primary.text if primary else None,
                }
            )
        if allowed_ids is not None and not {p["word_id"] for p in parts} <= allowed_ids:
            reason = reason or "ИИ взял слово не из списка"
        try:
            usefulness = int(item["u"]) if item.get("u") is not None else None
        except (TypeError, ValueError):
            usefulness = None
        if not reason and usefulness is not None and usefulness < MIN_USEFULNESS:
            reason = f"ИИ: слабая фраза (полезность {usefulness}/5)"
        if not reason and not 2 <= len(parts) <= 5:
            reason = "Нужно от 2 до 5 слов"
        text = " ".join(p["text"] for p in parts)
        text = text[:1].upper() + text[1:]
        full = str(item.get("t") or "").strip()
        if broken and full:
            text = full
        if not reason and full and normalize_answer(full) != normalize_answer(text):
            reason = f"Части «{text}» не совпадают с правильной фразой «{full}» (нужного слова/формы нет в словаре)"
        content = {p["word_id"] for p in parts if p["role"] in ("noun", "verb", "adjective", "adverb")}
        if not reason:
            repeated = [words[i].word for i in content if content_use.get(i, 0) >= 2]
            if repeated:
                reason = f"Слово «{repeated[0]}» уже в 2 фразах этой пачки — нужно разнообразие"
            overused = [words[i].word for i in content if saved_use.get(i, 0) + content_use.get(i, 0) >= WORD_USE_CAP]
            if not reason and overused:
                reason = f"Слово «{overused[0]}» уже в {WORD_USE_CAP} мини-фразах — возьмите другие слова"
        if not reason and normalize_answer(text) in existing_texts:
            reason = "Такая мини-фраза уже есть"
        tg = str(item.get("tg") or "").strip()
        if not reason and not tg:
            reason = "Нет перевода на таджикский"
        roles = [p["role"] for p in parts]
        name = _template_name(roles) if parts else ""
        ids = {p["word_id"] for p in parts}
        sim, similar_to, similar_source = score(text, ids, batch) if parts else (0, None, None)
        if not reason:
            batch.append((text, ids))
            for i in content:
                content_use[i] = content_use.get(i, 0) + 1
        out.append(
            {
                "key": str(item["key"] if item.get("key") is not None else item.get("k", len(out))),
                "text": text,
                "translation_tg": tg,
                "translation_uz": str(item.get("uz") or "").strip() or None,
                "translation_en": str(item.get("en") or "").strip() or None,
                "parts": parts,
                "template_name": name,
                "template_exists": name in templates,
                "valid": reason is None,
                "reason": reason,
                "similarity": sim,
                "similar_to": similar_to,
                "similar_source": similar_source,
                "too_similar": sim >= SIMILAR_THRESHOLD,
                "usefulness": usefulness,
                "situation": str(item.get("s") or "").strip() or None,
                # A part could not be matched to a dictionary word: never savable.
                "broken": broken or not parts,
            }
        )
    return out


def _topic(db: Session, dictionary: Dictionary, category_id: int | None) -> tuple[str, int | None]:
    if category_id is None:
        return "", None
    category = db.get(Category, category_id)
    if category is None or category.dictionary_id != dictionary.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Тема не найдена")
    return category.name, category.id


def generate(db: Session, dictionary: Dictionary, count: int, category_id: int | None = None) -> dict:
    topic, category_id = _topic(db, dictionary, category_id)
    words = word_list(db, dictionary, category_id)
    if len(words) < 2:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Слишком мало слов для фраз — добавьте слова (см. «Не хватает слов»)",
        )
    avoid = [t for (t,) in db.query(MiniPhrase.text).filter(MiniPhrase.dictionary_id == dictionary.id).limit(150)]
    langs = translation_languages()
    raw, needs, tokens = ai_phrases(db, words, count, topic, avoid, langs)
    # Переводы живут отдельно от проверки структуры фразы: саму фразу проверяет
    # скрипт (слова из словаря, формы, повторы), а переводы -- дело модели.
    translations_by_key = {
        str(item.get("key")): {
            str(code).strip().lower(): str(text).strip()
            for code, text in (item.get("tr") or {}).items()
            if str(text or "").strip()
        }
        for item in raw
    }
    known = _known_tokens(_words(db, dictionary.id), dictionary.language)
    needs = [n for n in needs if n["text"] not in known]
    for i, item in enumerate(raw):
        item.setdefault("key", f"g{i}")
    allowed = {w.id for w in words}
    items = check_candidates(db, dictionary, raw, allowed)
    items, fix_tokens, fixed = self_review(db, dictionary, words, raw, items, allowed)
    # Only phrases the critic rated MIN_STARS+ are kept (similar ones go to «Похожие» for the admin).
    keep = [i for i in items if i["valid"] and (i["too_similar"] or i.get("stars", 0) >= MIN_STARS)]
    dropped = len(items) - len(keep)
    items = keep
    for item in items:
        item["translations"] = translations_by_key.get(str(item.get("key")), {})
    return {
        "items": items,
        "tokens": tokens + fix_tokens,
        "words_sent": len(words),
        "suggested_words": needs,
        "auto_fixed": fixed,
        "dropped": dropped,
        "languages": [code for code, _ in langs],
    }


_FIX_SYSTEM = (
    "You are an experienced Russian teacher for adult Tajik/Uzbek beginners reviewing your own draft. Input: "
    "{\"w\":\"id:word,...\" (the ONLY words allowed),\"have\":[phrases that already exist],\"r\":[{\"k\":key,"
    "\"was\":\"draft phrase\",\"why\":\"what the automatic check found\"}]}. For each item fix the problem: "
    "correct the phrase or replace it with a different one. The result must be a 2-5 word phrase really used in "
    "conversation, 100% correct natural Russian, every word in its exact form a form of the w word whose id you "
    "give (if a word/form is missing from w, pick another phrase), meaning clearly different from have and from "
    "each other. Check it yourself before replying. Rate u 1-5. Reply JSON only: {\"r\":[{\"k\":key,\"t\":"
    "\"full phrase\",\"p\":[[id,\"word exactly as in t\"],...],\"u\":5,\"s\":\"situation\",\"tg\":\"Tajik\","
    "\"uz\":\"Uzbek (Latin)\",\"en\":\"English\"}]}."
)

SELF_REVIEW_ROUNDS = 3


_CRITIC_SYSTEM = (
    "You are a strict native-speaker Russian editor and teacher of adult Tajik/Uzbek beginners. Input: "
    "{\"r\":[{\"k\":key,\"t\":\"phrase\",\"tg\":\"Tajik translation\"}]}. Think carefully and read every "
    "phrase several times. Give each phrase stars 1-5: 5 = perfect, natural Russian a person really says, clear "
    "meaning, very useful in everyday conversation, correct Tajik translation; 4 = good and useful; 3 or less = any "
    "grammar mistake (case, person, gender, aspect, word order), unnatural or odd («Вода молодая»), unclear meaning, "
    "rarely useful, wrong Tajik translation, or repeats the meaning of another phrase in the list. Be strict — only "
    "really good phrases get 4-5. Reply JSON only: {\"r\":[{\"k\":key,\"stars\":5,\"why\":\"short reason in "
    "Russian if below 4\"}]} with EVERY phrase."
)

MIN_STARS = 4


def critic(db: Session, items: list[dict]) -> tuple[dict[str, str], int]:
    """A second, independent AI pass over the phrases that passed the script:
    it rates every phrase 1-5 stars (stored as item["stars"]); below
    MIN_STARS is returned as {key: reason}. A phrase it forgot to rate counts
    as not rated, i.e. rejected."""
    good = [i for i in items if i["valid"] and not i["too_similar"] and i.get("stars", 0) < MIN_STARS]
    if not good:
        return {}, 0
    try:
        data, used = chat(
            db,
            _CRITIC_SYSTEM,
            {"r": [{"k": i["key"], "t": i["text"], "tg": i["translation_tg"]} for i in good]},
            max_tokens=45 * len(good) + 300,
        )
    except HTTPException:
        return {}, 0
    rated = {str(r.get("k")): r for r in data.get("r") or [] if isinstance(r, dict)}
    bad: dict[str, str] = {}
    for i in good:
        r = rated.get(i["key"])
        try:
            stars = int(r.get("stars")) if r else 0
        except (TypeError, ValueError):
            stars = 0
        i["stars"] = stars
        if stars < MIN_STARS:
            why = str((r or {}).get("why") or "не оценена").strip()[:120]
            bad[i["key"]] = f"ИИ-оценка {stars}★: {why}"
    return bad, used


def self_review(db: Session, dictionary: Dictionary, words: list[Word], raw: list[dict], items: list[dict], allowed: set[int]):
    """The model checks its own work before the admin sees it: everything the
    script rejected or found too similar goes back with the exact reason, and
    the fixed versions are checked again -- up to SELF_REVIEW_ROUNDS times.
    Only what still fails after that reaches «Отклонённые» / «Похожие»."""
    tokens = 0
    touched: set[str] = set()
    have = [t for (t,) in db.query(MiniPhrase.text).filter(MiniPhrase.dictionary_id == dictionary.id).limit(150)]
    for _ in range(SELF_REVIEW_ROUNDS):
        flagged, used = critic(db, items)
        tokens += used
        for i in items:
            if i["key"] in flagged:
                i["valid"], i["reason"] = False, flagged[i["key"]]
        bad = [i for i in items if not i["valid"] or i["too_similar"]]
        if not bad:
            break
        why = {
            i["key"]: i["reason"] if not i["valid"] else f"слишком похожа на «{i['similar_to']}» ({i['similarity']}%)"
            for i in bad
        }
        good_texts = [i["text"] for i in items if i["valid"] and not i["too_similar"]]
        payload = [{"k": i["key"], "was": i["text"], "why": why[i["key"]]} for i in bad[:30]]
        try:
            data, used = chat(
                db,
                _FIX_SYSTEM,
                {"w": _compact(words), "have": (have + good_texts)[-180:], "r": payload},
                max_tokens=190 * len(payload) + 300,
            )
        except HTTPException:
            break
        tokens += used
        answers = {str(a.get("k")): a for a in data.get("r") or [] if isinstance(a, dict)}
        if not answers:
            break
        # Re-check the whole batch in order so repeats/similarity see the fixes.
        new_raw = []
        for item, old in zip(raw, items):
            fix = answers.get(old["key"]) if old["key"] in why else None
            if fix is not None:
                fix = dict(fix, key=old["key"])
                new_raw.append(fix)
            else:
                new_raw.append(item)
        new_items = check_candidates(db, dictionary, new_raw, allowed)
        for o, n in zip(items, new_items):
            if o["key"] not in answers and "stars" in o:
                n["stars"] = o["stars"]  # unchanged phrase: keep its rating, don't pay twice
        touched |= set(answers) & set(why)
        raw, items = new_raw, new_items
    # The last fixes get the same independent check; what still fails is dropped.
    flagged, used = critic(db, items)
    tokens += used
    for i in items:
        if i["key"] in flagged:
            i["valid"], i["reason"] = False, flagged[i["key"]]
    fixed = sum(1 for i in items if i["key"] in touched and i["valid"] and not i["too_similar"])
    return items, tokens, fixed


_REPHRASE_SYSTEM = (
    "You are an experienced Russian teacher for adult Tajik/Uzbek beginners. Input: {\"w\":\"id:word,...\" (the ONLY "
    "words allowed),\"langs\":\"code:name,...\" (translate into every one of them),"
    "\"r\":[{\"k\":key,\"was\":\"phrase\",\"like\":\"an existing phrase\"}]}. For each, write ONE "
    "new phrase of 2-5 words that is genuinely useful in real conversation (question, request, answer, politeness, "
    "need, plan, feeling, opinion), 100% correct natural Russian, and means something clearly different from both was "
    "and like. Every word in its exact form must be a form of the w word whose id you give; if a needed word/form is "
    "missing from w, choose another phrase. Check each answer before replying. Rate u 1-5 how often a beginner needs "
    "it. Reply JSON only: {\"r\":[{\"k\":key,\"t\":\"full phrase\",\"p\":[[id,\"word exactly as in t\"],...],"
    "\"u\":5,\"s\":\"situation\",\"tr\":{\"<code from langs>\":\"translation\"}}]}."
)


def rephrase(db: Session, dictionary: Dictionary, items: list[dict], category_id: int | None = None) -> dict:
    _, category_id = _topic(db, dictionary, category_id)
    words = word_list(db, dictionary, category_id)
    langs = translation_languages()
    payload_items = [
        {"k": str(item.get("key")), "was": item.get("text"), "like": item.get("similar_to") or ""} for item in items[:30]
    ]
    if not payload_items:
        return {"items": [], "tokens": 0}
    data, tokens = chat(
        db,
        _REPHRASE_SYSTEM,
        {"w": _compact(words), "r": payload_items, "langs": _langs_payload(langs)},
        max_tokens=(170 + 50 * len(langs)) * len(payload_items) + 200,
    )
    raw = [i for i in data.get("r") or [] if isinstance(i, dict)]
    for i in raw:
        i["key"] = str(i.get("k"))
    translations_by_key = {
        str(i.get("key")): {
            str(code).strip().lower(): str(text).strip()
            for code, text in (i.get("tr") or {}).items()
            if str(text or "").strip()
        }
        for i in raw
    }
    allowed = {w.id for w in words}
    items = check_candidates(db, dictionary, raw, allowed)
    items, fix_tokens, _ = self_review(db, dictionary, words, raw, items, allowed)
    kept = [i for i in items if i["valid"]]
    for item in kept:
        item["translations"] = translations_by_key.get(str(item.get("key")), {})
    return {"items": kept, "tokens": tokens + fix_tokens}


# --- Saving the chosen ones (script only) -----------------------------------------


def save(db: Session, dictionary: Dictionary, items: list[dict]) -> dict:
    created, skipped, forms_added, templates_created = [], [], [], []
    for item in items:
        # Переводы: приходят словарём по кодам языков. Старые три поля остаются
        # для совместимости, остальные языки живут в mini_phrase_translations.
        translations = {
            str(code).strip().lower(): str(text).strip()
            for code, text in (item.get("translations") or {}).items()
            if str(text or "").strip()
        }
        for code, value in (
            ("tg", item.get("translation_tg")),
            ("uz", item.get("translation_uz")),
            ("en", item.get("translation_en")),
        ):
            if value and str(value).strip() and code not in translations:
                translations[code] = str(value).strip()

        raw = {
            "key": item.get("key"),
            "p": [[p.get("word_id"), p.get("text")] for p in item.get("parts", [])],
            "tg": translations.get("tg"),
            "uz": translations.get("uz"),
            "en": translations.get("en"),
        }
        checked = check_candidates(db, dictionary, [raw])[0]
        if not checked["valid"] and item.get("force"):
            # The admin chose a rejected phrase by hand: only the hard rules
            # still apply -- real dictionary words, a Tajik translation, no
            # exact duplicate. Usefulness, length, repeats etc. are the
            # admin's call.
            existing = {normalize_answer(t) for (t,) in db.query(MiniPhrase.text).filter(MiniPhrase.dictionary_id == dictionary.id)}
            if checked["broken"] or item.get("broken"):
                checked["reason"] = "Есть слово не из словаря — такую фразу нельзя сохранить"
            elif not checked["translation_tg"]:
                checked["reason"] = "Нет перевода на таджикский"
            elif normalize_answer(checked["text"]) in existing:
                checked["reason"] = "Такая мини-фраза уже есть"
            else:
                checked["valid"] = True
        if not checked["valid"]:
            skipped.append({"text": checked["text"], "reason": checked["reason"]})
            continue
        roles = [p["role"] for p in checked["parts"]]
        name = checked["template_name"]
        template = db.query(MiniPhraseTemplate).filter(MiniPhraseTemplate.name == name).first()
        if template is None:
            template = MiniPhraseTemplate(name=name, distractor_count=2, enabled=True, **_template_texts(roles))
            db.add(template)
            db.flush()
            templates_created.append(name)
        mp = MiniPhrase(
            dictionary_id=dictionary.id,
            template_id=template.id,
            text=checked["text"],
            translation_tg=checked["translation_tg"],
            translation_uz=checked["translation_uz"],
            translation_en=checked["translation_en"],
            enabled=True,
        )
        db.add(mp)
        db.flush()
        # Одна строка на язык: поэтому пятый язык сохраняется без миграции
        # колонок и без правки кода.
        for code, text in translations.items():
            db.add(
                MiniPhraseTranslation(mini_phrase_id=mp.id, language=code, text=text[:1000])
            )
        for position, p in enumerate(checked["parts"], start=1):
            word = db.get(Word, p["word_id"])
            if word.role is None:
                word.role = p["role"]
            # Роль пишется И в языковую запись того языка, на котором собрана
            # фраза: роль принадлежит языку, и правка одного языка не должна
            # менять роль в остальных.
            phrase_lang = phrase_language(dictionary)
            entry = (
                db.query(WordEntry)
                .filter(WordEntry.concept_id == word.id, WordEntry.language == phrase_lang)
                .first()
            )
            if entry is not None and entry.role is None:
                entry.role = p["role"]
            form_id = None
            if p["text"].lower() != word.word.strip().lower():
                form = next(
                    (f for f in word.forms if f.language == dictionary.language and f.text.strip().lower() == p["text"].lower()),
                    None,
                )
                if form is None:
                    form = WordForm(word_id=word.id, language=dictionary.language, text=p["text"].lower())
                    db.add(form)
                    db.flush()
                    if form not in word.forms:
                        word.forms.append(form)
                    forms_added.append(f"{word.word} → {form.text}")
                form_id = form.id
            mp.parts.append(MiniPhrasePart(position=position, text=p["text"], word_id=word.id, word_form_id=form_id))
        db.add(mp)
        db.flush()
        created.append(checked["text"])
    return {"created": created, "skipped": skipped, "forms_added": forms_added, "templates_created": templates_created}


# --- Adding missing words as full cards --------------------------------------------

_CARD_SYSTEM = (
    "You create Russian dictionary cards for Tajik/Uzbek-speaking learners. Input: {\"w\":[\"word or a form of it\",...],"
    "\"cats\":[\"existing category names\"]}. For each item return its dictionary (base) form and a full card. "
    "Reply JSON only: {\"r\":[{\"in\":\"input\",\"base\":\"base form\",\"role\":\"pronoun|verb|noun|adjective|adverb|"
    "preposition|number|other\",\"tr\":\"transcription in Cyrillic with stress mark or empty\",\"tg\":\"Tajik\","
    "\"uz\":\"Uzbek (Latin, oʻ gʻ)\",\"en\":\"English\",\"cat\":\"one of cats or empty\",\"imp\":1-5 (5 = beginners need "
    "it first),\"forms\":[\"all common Russian forms: verbs - present/future conjugation, past (m/f/n/pl), imperative; "
    "nouns - cases singular and plural; adjectives - gender/number/cases; pronouns - cases\"]}]}. "
    "Forms lowercase, no duplicates, without the base form itself."
)


def add_words(db: Session, dictionary: Dictionary, texts: list[str]) -> dict:
    texts = [t.strip().lower() for t in texts if t and t.strip()][:30]
    if not texts:
        return {"created": [], "updated": [], "tokens": 0}
    categories = {c.name: c for c in db.query(Category).filter(Category.dictionary_id == dictionary.id).all()}
    data, tokens = chat(db, _CARD_SYSTEM, {"w": texts, "cats": list(categories)}, max_tokens=420 * len(texts) + 200)
    existing_words = _words(db, dictionary.id)
    capitalize = sum(1 for w in existing_words if w.word[:1].isupper()) > len(existing_words) / 2
    created, updated = [], []
    for card in data.get("r") or []:
        if not isinstance(card, dict):
            continue
        base = str(card.get("base") or card.get("in") or "").strip().lower()
        if not base or len(base) > 60:
            continue
        role = card.get("role") if card.get("role") in WORD_ROLES else guess_role(base)
        forms = {str(f).strip().lower() for f in (card.get("forms") or []) if str(f).strip()}
        source = str(card.get("in") or "").strip().lower()
        if source and source != base:
            forms.add(source)
        forms.discard(base)
        word = (
            db.query(Word)
            .filter(Word.dictionary_id == dictionary.id, func.lower(func.trim(Word.word)) == base)
            .first()
        )
        if word is not None:
            have = {f.text.strip().lower() for f in word.forms if f.language == dictionary.language}
            added = sorted(forms - have)
            for f in added:
                db.add(WordForm(word_id=word.id, language=dictionary.language, text=f[:255]))
            if word.role is None:
                word.role = role
            updated.append({"word": word.word, "forms_added": len(added)})
            continue
        try:
            importance = max(1, min(5, int(card.get("imp") or 3)))
        except (TypeError, ValueError):
            importance = 3
        category = categories.get(str(card.get("cat") or ""))
        word = Word(
            dictionary_id=dictionary.id,
            word=base.capitalize() if capitalize else base,
            transcription=(str(card.get("tr") or "").strip() or None),
            importance=importance,
            role=role,
            category_id=category.id if category else None,
        )
        db.add(word)
        db.flush()
        for lang in ("tg", "uz", "en"):
            text = str(card.get(lang) or "").strip()
            if text:
                db.add(WordTranslation(word_id=word.id, language=lang, text=text[:255]))
        for f in sorted(forms):
            db.add(WordForm(word_id=word.id, language=dictionary.language, text=f[:255]))
        db.flush()
        created.append({"word": word.word, "forms": len(forms), "category": category.name if category else None})
    return {"created": created, "updated": updated, "tokens": tokens}
