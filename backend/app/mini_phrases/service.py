import re

from sqlalchemy.orm import Session

from app.core.content_language import (
    content_language,
    learning_language,
    mini_phrase_translation,
    phrase_translation,
    primary_translation,
    ui_language,
)
from app.core.storage import url_for_key
from app.mini_phrases.render import DEFAULT_EXPLANATIONS, render_explanation


def template_explanation(template, language: str) -> str | None:
    """Текст объяснения шаблона на нужном языке.

    Сначала таблица переводов (там столько языков, сколько в базе), затем
    старые колонки трёх языков, затем русский. Для языка без перевода вернётся
    None -- вызывающий возьмёт общее объяснение из DEFAULT_EXPLANATIONS.
    """
    if template is None:
        return None
    for row in getattr(template, "translations", None) or []:
        if row.language == language and (row.text or "").strip():
            return row.text
    legacy = getattr(template, f"explanation_{language}", None)
    if legacy and legacy.strip():
        return legacy
    return template.explanation_ru
from app.models.dictionary import Dictionary
from app.models.lesson import Lesson
from app.models.mini_phrase import (
    KIND_ORDERED_PARTS,
    LessonMiniPhrase,
    MiniPhrase,
    MiniPhraseSettings,
    UserMiniPhraseDone,
    UserMiniPhrasePoints,
)
from app.models.user import User
from app.word_entries import role_for
from app.models.word import Word
from app.models.word_progress import WordProgress
from app.schemas.mini_phrase import MiniPhraseOut


def get_mini_phrase_settings(db: Session) -> MiniPhraseSettings:
    settings = db.get(MiniPhraseSettings, 1)
    if settings is None:
        settings = MiniPhraseSettings(id=1)
        db.add(settings)
        db.flush()
    return settings


# --- Choosing a lesson's mini-phrases ---------------------------------------


def _learned_word_ids(db: Session, user_id: int, dictionary_id: int) -> set[int]:
    rows = (
        db.query(WordProgress.word_id)
        .join(Word, Word.id == WordProgress.word_id)
        .filter(WordProgress.user_id == user_id, WordProgress.mastered_at.isnot(None), Word.dictionary_id == dictionary_id)
        .all()
    )
    return {row[0] for row in rows}


def select_for_lesson(
    db: Session, user: User, dictionary_id: int, lesson_word_ids: list[int]
) -> list[MiniPhrase]:
    """The mini-phrases a lesson with these words opens: every part's word is
    already learned or taught in this lesson, at least one of them IS from
    this lesson (so it's this lesson that opens it), and the user hasn't
    gone through it before. At most the admin's per-lesson limit, in the
    admin's order (id).

    Берутся только записи того языка, который человек изучает."""
    limit = get_mini_phrase_settings(db).max_per_lesson
    dictionary = db.get(Dictionary, dictionary_id)
    dictionary_language = (dictionary.language if dictionary is not None else None) or "ru"
    lesson_set = set(lesson_word_ids)
    if limit <= 0 or not lesson_set:
        return []
    known = _learned_word_ids(db, user.id, dictionary_id) | lesson_set
    done = {
        row[0]
        for row in db.query(UserMiniPhraseDone.mini_phrase_id).filter(UserMiniPhraseDone.user_id == user.id).all()
    }
    chosen: list[MiniPhrase] = []
    # Показываем только записи того языка, который человек изучает: у одного
    # понятия теперь может быть несколько языковых записей («Я не понимаю» и
    # «Ман нафаҳмидам»), и учить нужно свою.
    target_language = learning_language() or dictionary_language
    candidates = (
        db.query(MiniPhrase)
        .filter(
            MiniPhrase.dictionary_id == dictionary_id,
            MiniPhrase.enabled.is_(True),
            (MiniPhrase.language == target_language) | (MiniPhrase.language.is_(None)),
        )
        .order_by(MiniPhrase.id)
        .all()
    )
    for mp in candidates:
        if mp.id in done or (mp.template is not None and not mp.template.enabled):
            continue
        # Readable in this user's translation language (no fallback, like phrases).
        if not _record_translation(db, mp, content_language()):
            continue
        word_ids = {p.word_id for p in mp.parts}
        if word_ids and word_ids <= known and word_ids & lesson_set:
            chosen.append(mp)
            if len(chosen) >= limit:
                break
    return chosen


def attach_to_lesson(db: Session, user: User, lesson: Lesson, lesson_word_ids: list[int]) -> None:
    for position, mp in enumerate(select_for_lesson(db, user, lesson.dictionary_id, lesson_word_ids)):
        db.add(LessonMiniPhrase(lesson_id=lesson.id, mini_phrase_id=mp.id, position=position))


# --- What the app shows -----------------------------------------------------


def _distractors(db: Session, user: User, mp: MiniPhrase, count: int) -> list[dict]:
    if count <= 0:
        return []
    from app.exercises.common import get_learned_pool
    from app.priority.distractors import prefer_distractor_words

    part_ids = {p.word_id for p in mp.parts}
    # Обманки должны быть на ТОМ ЖЕ языке, что и части фразы: иначе на доске
    # «Собери фразу» таджикские части лежат рядом с русскими плитками.
    language = mp.language or "ru"
    part_texts = {p.text.strip().lower() for p in mp.parts}
    pool = []
    for word in get_learned_pool(db, user.id, mp.dictionary_id):
        if word.id in part_ids:
            continue
        entry = next((e for e in word.language_entries if e.language == language), None)
        text = ((entry.text if entry is not None else "") or "").strip()
        if not text or text.lower() in part_texts:
            continue
        pool.append((word, text))

    picked = prefer_distractor_words(db, user.id, [word for word, _ in pool])[:count]
    texts = {word.id: text for word, text in pool}
    return [{"text": texts[word.id], "word_id": word.id} for word in picked if word.id in texts]


def _record_translation(db: Session, mp: MiniPhrase, reading: str) -> str | None:
    """Перевод фразы на язык, который человек читает.

    Запись мини-фразы — это фраза НА ОДНОМ языке, поэтому перевод ищется так:
    1. строки переводов этой записи (mini_phrase_translations);
    2. запись ТОГО ЖЕ понятия на языке чтения — например, русская пара к
       таджикской фразе;
    3. если запись сама на языке чтения — её собственный текст;
    4. старые колонки tg/uz/en — только для записей языка словаря: у фразы на
       другом языке эти колонки не про неё.
    """
    for row in getattr(mp, "translations", None) or []:
        if row.language == reading and (row.text or "").strip():
            return row.text

    if mp.concept_id is not None:
        sibling = (
            db.query(MiniPhrase)
            .filter(
                MiniPhrase.concept_id == mp.concept_id,
                MiniPhrase.language == reading,
                MiniPhrase.enabled.is_(True),
                MiniPhrase.id != mp.id,
            )
            .first()
        )
        if sibling is not None and (sibling.text or "").strip():
            return sibling.text

    own = mp.language or "ru"
    if own == reading:
        return mp.text
    if own == "ru":
        return mini_phrase_translation(mp)
    return None


def mini_phrase_out(db: Session, user: User, mp: MiniPhrase, *, with_distractors: bool = True) -> MiniPhraseOut:
    translation = _record_translation(db, mp, content_language()) or mp.translation_tg
    parts = []
    for p in mp.parts:
        primary = primary_translation(p.word) if p.word is not None else None
        parts.append(
            {
                "position": p.position,
                "text": p.text,
                "word_id": p.word_id,
                # Роль -- из языка самой фразы: в другом языке это же слово
                # может быть другой частью речи.
                "role": p.role
                or (role_for(db, p.word, mp.language) if p.word is not None else None),
                "translation": primary.text if primary else None,
            }
        )
    template = mp.template
    lang = ui_language()
    text = template_explanation(template, lang) if template is not None else None
    explanation = render_explanation(text or DEFAULT_EXPLANATIONS.get(lang, DEFAULT_EXPLANATIONS["ru"]), mp.text, translation, parts)
    count = template.distractor_count if template is not None else 2
    return MiniPhraseOut(
        id=mp.id,
        dictionary_id=mp.dictionary_id,
        text=mp.text,
        translation=translation,
        audio_url=url_for_key(mp.audio_key),
        template_kind=template.kind if template is not None else KIND_ORDERED_PARTS,
        parts=parts,
        explanation=explanation,
        distractors=_distractors(db, user, mp, count) if with_distractors else [],
    )


def lesson_mini_phrases_out(db: Session, user: User, lesson: Lesson) -> list[MiniPhraseOut]:
    rows = (
        db.query(LessonMiniPhrase)
        .filter(LessonMiniPhrase.lesson_id == lesson.id)
        .order_by(LessonMiniPhrase.position, LessonMiniPhrase.id)
        .all()
    )
    return [mini_phrase_out(db, user, row.mini_phrase) for row in rows if row.mini_phrase.enabled]


# --- Answers ----------------------------------------------------------------

_PUNCT = re.compile(r"[^\w\s]", re.UNICODE)


def normalize_answer(text: str) -> str:
    """Case and punctuation never matter."""
    return " ".join(_PUNCT.sub(" ", text.lower()).split())


def check_answer(mp: MiniPhrase, answer: list[str]) -> bool:
    given = normalize_answer(" ".join(answer))
    return bool(given) and (
        given == normalize_answer(mp.text) or given == normalize_answer(" ".join(p.text for p in mp.parts))
    )


def mark_done(db: Session, user_id: int, mini_phrase_id: int) -> None:
    exists = (
        db.query(UserMiniPhraseDone.id)
        .filter(UserMiniPhraseDone.user_id == user_id, UserMiniPhraseDone.mini_phrase_id == mini_phrase_id)
        .first()
    )
    if exists is None:
        db.add(UserMiniPhraseDone(user_id=user_id, mini_phrase_id=mini_phrase_id))


def award_points_once(db: Session, user: User, mini_phrase_id: int) -> int:
    """Rating points for assembling this mini-phrase right -- once per
    (user, mini-phrase), wherever it first happened. Returns the points."""
    from app.rating import grant_rating_points

    settings = get_mini_phrase_settings(db)
    points = settings.points_per_correct
    if not settings.points_enabled or points <= 0:
        return 0
    already = (
        db.query(UserMiniPhrasePoints.id)
        .filter(UserMiniPhrasePoints.user_id == user.id, UserMiniPhrasePoints.mini_phrase_id == mini_phrase_id)
        .first()
    )
    if already is not None:
        return 0
    grant_rating_points(db, user, points)
    db.add(UserMiniPhrasePoints(user_id=user.id, mini_phrase_id=mini_phrase_id, points_awarded=points))
    return points
