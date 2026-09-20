"""«Аналитика пользователей»: an admin-only, read-only report over data
that already fully exists -- Word/WordForm, WordProgress, Phrase -- built
on the EXACT SAME "is this phrase available" definition as the user-facing
"Мои фразы" (see app.routers.phrases: `_tokenize`, `_get_learned_word_
tokens`). Nothing here writes anything, defines a second notion of
"learned", or duplicates that matching algorithm -- it only asks more
detailed questions of it (which specific word(s) are missing, and what
would learning one specific word unlock) than the boolean `_phrase_is_
available` alone can answer.
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin
from app.database import get_db
from app.models.dictionary import Dictionary
from app.models.phrase import Phrase
from app.models.user import User
from app.models.word import Word
from app.models.word_progress import WordProgress
from app.routers.lessons import _get_threshold
from app.routers.phrases import _get_learned_word_tokens, _tokenize
from app.schemas.analytics import (
    AnalyticsDictionaryOut,
    MissingWordOut,
    NearPhraseOut,
    OpenPhraseAnalyticsOut,
    UserPhraseAnalyticsOut,
    WordImpactOut,
)

router = APIRouter(prefix="/admin/analytics", tags=["admin-analytics"])


@router.get("/dictionaries", response_model=list[AnalyticsDictionaryOut])
def list_analytics_dictionaries(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    """Only dictionaries with at least one Phrase -- a dictionary with none
    would always render an empty, useless report, so it's never offered as
    a choice here."""
    rows = (
        db.query(Dictionary, func.count(Phrase.id))
        .join(Phrase, Phrase.dictionary_id == Dictionary.id)
        .group_by(Dictionary.id)
        .order_by(Dictionary.id)
        .all()
    )
    return [
        AnalyticsDictionaryOut(id=d.id, name=d.name, language=d.language, phrase_count=count) for d, count in rows
    ]


def _build_token_to_word(db: Session, dictionary: Dictionary) -> tuple[dict[str, Word], list[Word]]:
    """Every token (a word's own text, or one of its OWN-LANGUAGE forms --
    same rule as `_get_learned_word_tokens`) mapped back to the Word it
    belongs to, for every Word in the dictionary, learned or not. This is
    what lets a "missing" token be reported as a real, nameable Word
    instead of just the raw phrase text."""
    words = db.query(Word).filter(Word.dictionary_id == dictionary.id).all()
    token_to_word: dict[str, Word] = {}
    for word in words:
        token_to_word.setdefault(word.word.strip().lower(), word)
        for form in word.forms:
            if form.language == dictionary.language:
                token_to_word.setdefault(form.text.strip().lower(), word)
    return token_to_word, words


def _phrase_progress(
    phrase: Phrase, learned_tokens: set[str], token_to_word: dict[str, Word]
) -> tuple[int, int, list[tuple[int | None, str]]]:
    """(total_count, learned_count, missing) for one phrase -- `missing` is
    the DISTINCT set of requirements still outstanding, one entry per
    distinct Word (never one entry per raw token: "может" and "могу" in
    the same phrase are one missing word, "мочь", not two), each as
    (word_id, display text) -- word_id is None when the token matches no
    Word/form in this dictionary at all (nothing learnable would ever
    satisfy it)."""
    requirements: dict[tuple[str, object], tuple[bool, int | None, str]] = {}
    for token in _tokenize(phrase.original):
        word = token_to_word.get(token)
        key = ("word", word.id) if word is not None else ("token", token)
        if key in requirements:
            continue
        satisfied = token in learned_tokens
        display_text = word.word if word is not None else token
        requirements[key] = (satisfied, word.id if word is not None else None, display_text)

    total = len(requirements)
    learned = sum(1 for satisfied, _, _ in requirements.values() if satisfied)
    missing = [(word_id, text) for satisfied, word_id, text in requirements.values() if not satisfied]
    return total, learned, missing


@router.get("/users/{user_id}", response_model=UserPhraseAnalyticsOut)
def get_user_phrase_analytics(
    user_id: int,
    dictionary_id: int,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    dictionary = db.get(Dictionary, dictionary_id)
    if dictionary is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dictionary not found")

    threshold = _get_threshold(db)
    learned_tokens = _get_learned_word_tokens(db, user.id, dictionary)
    token_to_word, all_words = _build_token_to_word(db, dictionary)

    learned_word_count = (
        db.query(func.count(Word.id))
        .join(WordProgress, WordProgress.word_id == Word.id)
        .filter(WordProgress.user_id == user.id, WordProgress.score >= threshold, Word.dictionary_id == dictionary.id)
        .scalar()
    )

    phrases = (
        db.query(Phrase)
        .filter(Phrase.dictionary_id == dictionary.id)
        .order_by(Phrase.id)
        .all()
    )

    def category_name(p: Phrase) -> str | None:
        return p.category.name if p.category is not None else None

    open_phrases: list[OpenPhraseAnalyticsOut] = []
    near_phrases: list[NearPhraseOut] = []
    # word_id -> [display text, [phrase originals it would immediately open]]
    word_impact: dict[int, list] = {}

    for phrase in phrases:
        total, learned, missing = _phrase_progress(phrase, learned_tokens, token_to_word)
        if total > 0 and learned == total:
            open_phrases.append(
                OpenPhraseAnalyticsOut(
                    phrase_id=phrase.id,
                    original=phrase.original,
                    translation_tg=phrase.translation_tg,
                    category_name=category_name(phrase),
                )
            )
            continue

        near_phrases.append(
            NearPhraseOut(
                phrase_id=phrase.id,
                original=phrase.original,
                translation_tg=phrase.translation_tg,
                category_name=category_name(phrase),
                learned_count=learned,
                total_count=total,
                missing_words=[MissingWordOut(word_id=wid, text=text) for wid, text in missing],
            )
        )

        if len(missing) == 1 and missing[0][0] is not None:
            word_id, text = missing[0]
            entry = word_impact.setdefault(word_id, [text, []])
            entry[1].append(phrase.original)

    near_phrases.sort(key=lambda p: (p.total_count - p.learned_count, p.total_count, p.phrase_id))

    top_words = [
        WordImpactOut(word_id=word_id, word=text, new_phrase_count=len(originals), sample_phrases=originals)
        for word_id, (text, originals) in word_impact.items()
    ]
    top_words.sort(key=lambda w: (-w.new_phrase_count, w.word))

    return UserPhraseAnalyticsOut(
        user_id=user.id,
        user_login=user.login,
        dictionary_id=dictionary.id,
        threshold=threshold,
        learned_word_count=learned_word_count,
        total_word_count=len(all_words),
        open_phrase_count=len(open_phrases),
        total_phrase_count=len(phrases),
        remaining_phrase_count=len(phrases) - len(open_phrases),
        open_phrases=open_phrases,
        near_phrases=near_phrases,
        top_words=top_words,
    )
