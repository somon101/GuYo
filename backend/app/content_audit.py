"""Аудит контента: сходятся ли слова фраз со словарём?

Две разные проблемы, у каждой — своя причина.

**Фразы** (`Phrase`) вообще не хранят ссылок на слова: только текст предложения.
Слова выводятся разбором `original` на токены и поиском каждого токена среди слов
словаря и их форм НА СВОЁМ языке — ровно то же правило, по которому
app/routers/phrases.py решает, доступна ли фраза человеку. Значит фраза может
спокойно использовать слово, которого в словаре нет, и до сих пор об этом никто не
узнавал: такая фраза просто никогда никому не показывалась, молча.

**Мини-фразы** (`MiniPhrase`) наоборот, всегда ссылаются на слово (`word_id`
обязателен), поэтому «слова нет в словаре» там невозможно. Но бывает другое: текст
части не совпадает ни со словом, ни с одной его формой («тете» при слове «тётя», у
которого формы «тете» нет) — в упражнении такое слово не подсветится, а при
следующем редактировании форму не выбрать.

Модуль только читает: ничего не пишет и не меняет.
"""

import re

from sqlalchemy.orm import Session

from app.models.dictionary import Dictionary
from app.models.mini_phrase import MiniPhrase
from app.models.phrase import Phrase
from app.models.word import Word

# The same token rule app/routers/phrases.py matches availability with: runs of
# letters, lowercased -- punctuation, digits and spaces are never tokens.
_TOKEN_RE = re.compile(r"[^\W\d_]+", re.UNICODE)


def tokenize(text: str) -> list[str]:
    return [t.lower() for t in _TOKEN_RE.findall(text)]


def word_tokens(db: Session, dictionary: Dictionary) -> dict[str, set[int]]:
    """token -> ids of the words that provide it: each word's own text plus its
    forms in the DICTIONARY'S OWN language (a "tg" form describes another
    language's grammar and can never appear in a sentence written in the
    dictionary's language)."""
    rows = db.query(Word).filter(Word.dictionary_id == dictionary.id).all()
    tokens: dict[str, set[int]] = {}
    for word in rows:
        tokens.setdefault(word.word.strip().lower(), set()).add(word.id)
        for form in word.forms:
            if form.language == dictionary.language:
                tokens.setdefault(form.text.strip().lower(), set()).add(word.id)
    return tokens


def audit_dictionary(db: Session, dictionary: Dictionary) -> dict:
    """The whole picture for one dictionary: which phrases need words it does not
    have (with those words ranked by how many phrases need them), and which
    mini-phrase parts disagree with the word they point at."""
    tokens = word_tokens(db, dictionary)

    phrases = db.query(Phrase).filter(Phrase.dictionary_id == dictionary.id).all()
    missing_phrases: list[dict] = []
    missing_counts: dict[str, int] = {}
    missing_example: dict[str, str] = {}
    ready_phrases = 0
    empty_phrases = 0
    for phrase in phrases:
        phrase_tokens = tokenize(phrase.original)
        if not phrase_tokens:
            # A phrase with no letters at all can never be available to anyone --
            # there is nothing to have "fully learned".
            empty_phrases += 1
            continue
        missing = sorted({t for t in phrase_tokens if t not in tokens})
        if not missing:
            ready_phrases += 1
            continue
        for token in missing:
            missing_counts[token] = missing_counts.get(token, 0) + 1
            missing_example.setdefault(token, phrase.original)
        missing_phrases.append({"id": phrase.id, "original": phrase.original, "missing": missing})

    mini = db.query(MiniPhrase).filter(MiniPhrase.dictionary_id == dictionary.id).all()
    part_issues: list[dict] = []
    for mp in mini:
        for part in mp.parts:
            own = {part.word.word.strip().lower()}
            own |= {f.text.strip().lower() for f in part.word.forms if f.language == dictionary.language}
            text = part.text.strip().lower()
            if text and text not in own:
                part_issues.append(
                    {
                        "mini_phrase_id": mp.id,
                        "mini_phrase": mp.text,
                        "position": part.position,
                        "part_text": part.text,
                        "word_id": part.word_id,
                        "word": part.word.word,
                        "word_form_id": part.word_form_id,
                    }
                )

    missing_words = [
        {"word": token, "phrases": count, "example": missing_example.get(token)}
        for token, count in sorted(missing_counts.items(), key=lambda item: (-item[1], item[0]))
    ]

    return {
        "dictionary_id": dictionary.id,
        "dictionary_language": dictionary.language,
        # Every token a phrase can match against: words + their own-language forms.
        "tokens_available": len(tokens),
        "words_in_dictionary": db.query(Word).filter(Word.dictionary_id == dictionary.id).count(),
        "phrases": {
            "total": len(phrases),
            "ready": ready_phrases,
            "with_missing_words": len(missing_phrases),
            "empty": empty_phrases,
            "items": missing_phrases,
        },
        "missing_words": missing_words,
        "mini_phrases": {
            "total": len(mini),
            "parts_total": sum(len(mp.parts) for mp in mini),
            "parts_without_matching_form": len(part_issues),
            "items": part_issues,
        },
    }
