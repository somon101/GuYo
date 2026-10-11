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
- checking every phrase the model returns (words from the list only, 2-4,
  not a duplicate, has Tajik, usefulness >= 4), the similarity to what
  exists, choosing/creating templates, adding missing word forms on save.

What the MODEL does: invents sensible everyday phrases from that list (picking
the words itself, so they mean something), puts the words into the right
forms, rates usefulness, says where it's said and translates (tg/uz/en);
rebuilds a phrase that came out too similar; builds full word cards
(translations + all forms) for new words.
Nothing is saved until the admin picks what to keep.
"""

import difflib
import json
import re

import requests
from fastapi import HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.content_language import primary_translation
from app.mini_phrases.service import normalize_answer
from app.models.category import Category
from app.models.dictionary import Dictionary
from app.models.mini_phrase import WORD_ROLES, MiniPhrase, MiniPhrasePart, MiniPhraseTemplate
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


def role_of(word: Word) -> str:
    return word.role or guess_role(word.word)


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

_PHRASE_SYSTEM = (
    "You are a Russian teacher writing short practice phrases for beginners whose native language is Tajik or "
    "Uzbek. Input: {\"n\":how many,\"topic\":\"topic or empty\",\"w\":\"id:word,id:word,...\" (the ONLY words "
    "you may use),\"avoid\":[existing phrases]}. Write n DIFFERENT phrases of 2-4 words that a learner really says "
    "in everyday life: about themselves and family, food and drink, home, study and work, greetings, simple needs "
    "and feelings, asking and answering (e.g. «Я пью чай», «Мама готовит обед», «Я не понял», «Где ты живёшь»). "
    "Every word of a phrase must come from w (any grammatical form of it is fine: падеж, лицо, время). Each phrase "
    "must make full sense on its own; no odd or absurd combinations; vary the situations and the words; do not "
    "repeat or closely copy anything in avoid. Rate each: u = how useful for a beginner, 1-5 (5 = said daily). "
    "Reply JSON only: {\"r\":[{\"p\":[[id,\"word as written in the phrase\"],...],\"u\":5,"
    "\"s\":\"where it is said, 2-4 Russian words\",\"tg\":\"Tajik\",\"uz\":\"Uzbek (Latin, oʻ gʻ)\","
    "\"en\":\"English\"}]}. Parts in phrase order; lowercase except the first letter is not needed."
)


def word_list(db: Session, dictionary: Dictionary, category_id: int | None, limit: int = 260) -> list[Word]:
    """The words sent to the model: the chosen topic's words (or all) plus the
    anchor words every phrase leans on -- pronouns and the most important
    verbs -- in a compact `id:word` form. Fewer, related words make sensible
    phrases AND cost fewer tokens."""
    words = _words(db, dictionary.id)
    anchors = [w for w in words if role_of(w) == "pronoun"]
    anchors += sorted((w for w in words if role_of(w) == "verb"), key=lambda w: -w.importance)[:40]
    topic = [w for w in words if category_id is None or w.category_id == category_id]
    topic.sort(key=lambda w: -w.importance)
    picked = {w.id: w for w in anchors}
    for w in topic:
        if len(picked) >= limit:
            break
        picked.setdefault(w.id, w)
    return list(picked.values())


def _compact(words: list[Word]) -> str:
    return ",".join(f"{w.id}:{w.word.strip().lower()}" for w in words)


def ai_phrases(db: Session, words: list[Word], count: int, topic: str, avoid: list[str]) -> tuple[list[dict], int]:
    results: list[dict] = []
    tokens = 0
    remaining = count
    seen = list(avoid)
    while remaining > 0:
        n = min(25, remaining)
        data, used = chat(
            db,
            _PHRASE_SYSTEM,
            {"n": n, "topic": topic, "w": _compact(words), "avoid": seen[-60:]},
            max_tokens=170 * n + 200,
        )
        tokens += used
        got = [i for i in data.get("r") or [] if isinstance(i, dict)]
        results += got
        seen += [" ".join(str(x[1]) for x in i.get("p") or [] if isinstance(x, (list, tuple)) and len(x) == 2) for i in got]
        remaining -= n
    return results, tokens


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


def _similarity(db: Session, dictionary_id: int):
    """Returns a function scoring a candidate (text, word_ids) against what
    exists: existing mini-phrases (by word and text), «Мои фразы» (by text)
    and earlier candidates of the same batch."""
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
        a = normalize_answer(text)
        tokens_a = set(a.split())
        best = (0, None, None)
        for other_text, other_ids, source in existing + [(t, i, "batch") for t, i in batch]:
            b = normalize_answer(other_text)
            seq = difflib.SequenceMatcher(None, a, b).ratio()
            if other_ids is not None:
                overlap = len(word_ids & other_ids) / max(1, len(word_ids | other_ids))
            else:
                tb = set(b.split())
                overlap = len(tokens_a & tb) / max(1, len(tokens_a | tb))
            value = round(100 * (0.5 * seq + 0.5 * overlap))
            if value > best[0]:
                best = (value, other_text, source)
        return best

    return score


def check_candidates(db: Session, dictionary: Dictionary, raw: list[dict], allowed_ids: set[int] | None = None) -> list[dict]:
    """Turns the model's (or the admin's) items into checked preview items."""
    words = {w.id: w for w in _words(db, dictionary.id)}
    existing_texts = {normalize_answer(t) for (t,) in db.query(MiniPhrase.text).filter(MiniPhrase.dictionary_id == dictionary.id)}
    templates = {t.name: t for t in db.query(MiniPhraseTemplate).all()}
    score = _similarity(db, dictionary.id)
    batch: list[tuple[str, set[int]]] = []
    out = []
    for item in raw:
        reason = None
        if item.get("ok") is False:
            reason = "ИИ: из этих слов не получается естественная фраза"
        parts_in = item.get("p") or []
        parts = []
        for p in parts_in:
            if not isinstance(p, (list, tuple)) or len(p) != 2:
                reason = reason or "Неверный формат частей"
                continue
            wid, text = p
            word = words.get(wid) if isinstance(wid, int) else None
            text = str(text).strip()
            if word is None or not text:
                reason = reason or "Слово не из этого словаря"
                continue
            known = {word.word.strip().lower()} | {
                f.text.strip().lower() for f in word.forms if f.language == dictionary.language
            }
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
        if not reason and not 2 <= len(parts) <= 4:
            reason = "Нужно от 2 до 4 слов"
        text = " ".join(p["text"] for p in parts)
        text = text[:1].upper() + text[1:]
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
    avoid = [t for (t,) in db.query(MiniPhrase.text).filter(MiniPhrase.dictionary_id == dictionary.id).limit(60)]
    raw, tokens = ai_phrases(db, words, count, topic, avoid)
    for i, item in enumerate(raw):
        item.setdefault("key", f"g{i}")
    items = check_candidates(db, dictionary, raw, {w.id for w in words})
    return {"items": items, "tokens": tokens, "words_sent": len(words)}


_REPHRASE_SYSTEM = (
    "You rewrite Russian beginner practice phrases that came out too similar to existing ones. Input: "
    "{\"w\":\"id:word,...\" (the ONLY words allowed),\"r\":[{\"k\":key,\"was\":\"phrase\",\"like\":\"similar existing phrase\"}]}. "
    "For each, write ONE new natural everyday phrase of 2-4 words from w (any grammatical form), with a clearly "
    "different meaning or situation from both was and like, that a beginner would really say. Rate u 1-5 usefulness. "
    "Reply JSON only: {\"r\":[{\"k\":key,\"p\":[[id,\"word as written\"],...],\"u\":5,\"s\":\"where it is said\","
    "\"tg\":\"Tajik\",\"uz\":\"Uzbek (Latin)\",\"en\":\"English\"}]}."
)


def rephrase(db: Session, dictionary: Dictionary, items: list[dict], category_id: int | None = None) -> dict:
    _, category_id = _topic(db, dictionary, category_id)
    words = word_list(db, dictionary, category_id)
    payload_items = [
        {"k": str(item.get("key")), "was": item.get("text"), "like": item.get("similar_to") or ""} for item in items[:30]
    ]
    if not payload_items:
        return {"items": [], "tokens": 0}
    data, tokens = chat(
        db, _REPHRASE_SYSTEM, {"w": _compact(words), "r": payload_items}, max_tokens=170 * len(payload_items) + 200
    )
    raw = [i for i in data.get("r") or [] if isinstance(i, dict)]
    for i in raw:
        i["key"] = str(i.get("k"))
    return {"items": check_candidates(db, dictionary, raw, {w.id for w in words}), "tokens": tokens}


# --- Saving the chosen ones (script only) -----------------------------------------


def save(db: Session, dictionary: Dictionary, items: list[dict]) -> dict:
    created, skipped, forms_added, templates_created = [], [], [], []
    for item in items:
        raw = {
            "key": item.get("key"),
            "p": [[p.get("word_id"), p.get("text")] for p in item.get("parts", [])],
            "tg": item.get("translation_tg"),
            "uz": item.get("translation_uz"),
            "en": item.get("translation_en"),
        }
        checked = check_candidates(db, dictionary, [raw])[0]
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
        for position, p in enumerate(checked["parts"], start=1):
            word = db.get(Word, p["word_id"])
            if word.role is None:
                word.role = p["role"]
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
