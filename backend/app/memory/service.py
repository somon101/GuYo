"""The memory model: how likely a user is to recall a word right now.

Built on FSRS (py-fsrs, MIT): each (user, word) pair has a stability S --
days until the chance of recall falls to 90% -- and a difficulty D, and the
recall probability R decays with time since the last review. GuYo's own
layer on top decides what counts as one review and how good it was:

- One Asia/Dushanbe calendar day is one review. A lesson runs every word
  through several exercises within minutes; answers that close together
  barely strengthen long-term memory, so they are judged together.
- The day's grade comes from what the answers prove. A real wrong answer
  means the word wasn't recalled (Again). Getting everything right only
  in recognition exercises -- where the options can be eliminated or
  guessed -- is weaker evidence (Hard) than producing the word in a recall
  exercise (Good). A day whose only misses were timeouts counts as Hard:
  slow, not forgotten.
- The pre-lesson check (exercise "check") is the learner's own word on how
  well a word is already known: right + "hard" / "normal" / "easy" lifts the
  day's grade to Hard / Good / Easy (never above what a miss in the lesson
  allows). A wrong check, or a right one rated "guess", is only recorded:
  the lesson itself decides what the word proved.

State is always rebuilt from the full answer history (never patched
incrementally), so it cannot drift from the attempts that produced it.

For now the model runs alongside the existing Priority system and drives
nothing yet: it is computed and stored so its predictions can be checked
against real outcomes before anything relies on it.
"""

from collections import OrderedDict
from datetime import datetime, timezone

from fsrs import Card, Rating, Scheduler, State
from sqlalchemy import and_, func
from sqlalchemy.orm import Session

from app.core.dates import DUSHANBE_TZ, utc_now
from app.models.word_attempt import WordAttempt
from app.models.word_progress import WordProgress

DESIRED_RETENTION = 0.9
RECALL_EXERCISES = {"build_word", "speaking_word"}
CHECK_KEY = "check"
CHECK_GRADES = {"hard": Rating.Hard, "normal": Rating.Good, "easy": Rating.Easy}

# Day-level reviews: no minute-scale learning steps, no random interval
# fuzz -- the model must be a deterministic function of the history.
_scheduler = Scheduler(
    desired_retention=DESIRED_RETENTION,
    learning_steps=(),
    relearning_steps=(),
    enable_fuzzing=False,
)


def _utc(value: datetime) -> datetime:
    """py-fsrs only accepts timezone-aware UTC datetimes."""
    return value.astimezone(timezone.utc)


def _counts(attempt: WordAttempt) -> bool:
    """A check answer counts only when it was right and rated hard / normal /
    easy; every other check answer is just a record."""
    if attempt.exercise_key != CHECK_KEY:
        return True
    return bool(attempt.is_correct) and attempt.self_rating in CHECK_GRADES


def day_grade(attempts: list[WordAttempt]) -> Rating:
    """One review day as one FSRS grade (see the module docstring)."""
    checks = [a for a in attempts if a.exercise_key == CHECK_KEY and _counts(a)]
    lesson = [a for a in attempts if a.exercise_key != CHECK_KEY]
    base = _lesson_grade(lesson) if lesson else None
    if not checks:
        return base
    from_check = max((CHECK_GRADES[a.self_rating] for a in checks), key=lambda r: r.value)
    if base is None:
        return from_check
    return base if base == Rating.Again else max(base, from_check, key=lambda r: r.value)


def _lesson_grade(attempts: list[WordAttempt]) -> Rating:
    """Forgotten (Again) only when the day's real misses outnumber its right
    answers, or the day ended on a miss: a single slip among right answers (a
    mixed-up pair in Matching) used to count as forgetting the word and drove
    stability to hours."""
    real = [a for a in attempts if not a.timed_out]
    misses = sum(1 for a in real if not a.is_correct)
    hits = len(real) - misses
    if real and (misses > hits or not real[-1].is_correct):
        return Rating.Again
    if misses or any(a.timed_out for a in attempts):
        return Rating.Hard
    if any(a.exercise_key in RECALL_EXERCISES for a in attempts):
        return Rating.Good
    return Rating.Hard


def _days(attempts: list[WordAttempt]) -> "OrderedDict[object, list[WordAttempt]]":
    days: OrderedDict = OrderedDict()
    for a in attempts:
        if not _counts(a):
            continue
        days.setdefault(a.created_at.astimezone(DUSHANBE_TZ).date(), []).append(a)
    return days


def replay(attempts: list[WordAttempt], until: datetime | None = None) -> tuple[Card | None, int]:
    """The card after every review day strictly before `until` (all of
    them when None), and how many review days that was."""
    card = Card()
    count = 0
    for day, day_attempts in _days(attempts).items():
        first = day_attempts[0].created_at
        if until is not None and first >= until:
            break
        card, _ = _scheduler.review_card(card, day_grade(day_attempts), review_datetime=_utc(first))
        count += 1
    return (card if count else None), count


def recall_probability(progress: WordProgress, now: datetime | None = None) -> float | None:
    """R for this pair right now; None when the pair has no reviews yet."""
    if progress.memory_stability is None or progress.memory_last_review is None:
        return None
    card = Card(
        state=State.Review,
        stability=progress.memory_stability,
        difficulty=progress.memory_difficulty,
        last_review=_utc(progress.memory_last_review),
    )
    return _scheduler.get_card_retrievability(card, _utc(now or utc_now()))


def rebuild_memory(db: Session, progress: WordProgress) -> None:
    """Recomputes this pair's memory state from its whole answer history.
    Does NOT commit -- the caller owns the transaction."""
    attempts = (
        db.query(WordAttempt)
        .filter(WordAttempt.user_id == progress.user_id, WordAttempt.word_id == progress.word_id)
        .order_by(WordAttempt.created_at, WordAttempt.id)
        .all()
    )
    card, count = replay(attempts)
    progress.memory_review_days = count
    if card is None:
        progress.memory_stability = progress.memory_difficulty = progress.memory_last_review = None
        return
    progress.memory_stability = card.stability
    progress.memory_difficulty = card.difficulty
    progress.memory_last_review = card.last_review


def rebuild_pending_memories(db: Session, limit: int = 500) -> int:
    """Models pairs that have answers but no memory state yet -- the
    one-time backfill of history recorded before the model existed, done
    a batch at a time by the scheduler. Commits each batch."""
    has_attempts = (
        db.query(WordAttempt.id)
        .filter(and_(WordAttempt.user_id == WordProgress.user_id, WordAttempt.word_id == WordProgress.word_id))
        .exists()
    )
    pending = (
        db.query(WordProgress)
        .filter(WordProgress.memory_last_review.is_(None), has_attempts)
        .limit(limit)
        .all()
    )
    for progress in pending:
        rebuild_memory(db, progress)
    db.commit()
    return len(pending)


def memory_coverage(db: Session) -> tuple[int, int]:
    """(modelled pairs, pairs with at least one answer)."""
    modelled = db.query(func.count(WordProgress.id)).filter(WordProgress.memory_last_review.isnot(None)).scalar()
    total = db.query(func.count(func.distinct(func.concat(WordAttempt.user_id, "-", WordAttempt.word_id)))).scalar()
    return modelled or 0, total or 0


def secured_word_ids(db: Session, user_id: int, word_ids: list[int] | None) -> set[int]:
    """Words that need no more work in a lesson: the LEARNED ones
    (app/learning/mastery.py). Learned is for good -- a word the user is
    forgetting is reviewed through «Повторить сегодня» and Practice, it never
    goes back into lessons."""
    from app.learning.mastery import learned_ids

    return learned_ids(db, user_id, word_ids)


def due_progress_rows(db: Session, user_id: int, dictionary_id: int) -> list[tuple[float, WordProgress]]:
    """Learned words of this dictionary whose recall is below the target
    retention right now, most forgotten first, with that recall."""
    from app.models.word import Word
    from app.priority.settings import get_priority_settings

    settings = get_priority_settings(db)
    now = utc_now()
    rows = (
        db.query(WordProgress)
        .join(Word, Word.id == WordProgress.word_id)
        .filter(
            WordProgress.user_id == user_id,
            WordProgress.mastered_at.isnot(None),
            Word.dictionary_id == dictionary_id,
        )
        .all()
    )
    due = []
    for p in rows:
        r = recall_probability(p, now)
        if r is not None and r < settings.memory_target_retention:
            due.append((r, p))
    due.sort(key=lambda item: (item[0], item[1].word_id))
    return due


GRADE_NAMES = {Rating.Again: "again", Rating.Hard: "hard", Rating.Good: "good", Rating.Easy: "easy"}


def day_grade_reason(attempts: list[WordAttempt]) -> str:
    """The same rule as day_grade, said in words for Admin Web."""
    checks = [a for a in attempts if a.exercise_key == CHECK_KEY]
    lesson = [a for a in attempts if a.exercise_key != CHECK_KEY]
    check_text = ""
    if checks:
        names = {"hard": "трудно", "normal": "нормально", "easy": "легко"}
        said = ", ".join(sorted({names[a.self_rating] for a in checks if a.self_rating in names}))
        check_text = f"Проверка перед уроком: ответил верно и оценил «{said}»"
    if not lesson:
        return check_text
    text = _lesson_reason(lesson)
    return f"{text}. {check_text}" if check_text else text


def _lesson_reason(attempts: list[WordAttempt]) -> str:
    real = [a for a in attempts if not a.timed_out]
    misses = sum(1 for a in real if not a.is_correct)
    hits = len(real) - misses
    timeouts = sum(1 for a in attempts if a.timed_out)
    if real and misses > hits:
        return f"Ошибок ({misses}) больше, чем верных ответов ({hits}) — слово не вспомнилось"
    if real and not real[-1].is_correct:
        return "Последний ответ дня неверный — слово не вспомнилось"
    if misses:
        return f"{misses} ошибк. среди {hits} верных, но день закончился верным ответом — вспомнил с трудом"
    if timeouts:
        return f"Ошибок нет, но {timeouts} раз не успел ответить — вспомнил медленно"
    if any(a.exercise_key in RECALL_EXERCISES for a in attempts):
        return "Всё верно, и слово было собрано или произнесено самим — вспомнил хорошо"
    return "Всё верно, но только узнавание из вариантов (без «Собери слово» и речи) — слабое доказательство"


def _card_r(card: Card, at: datetime) -> float:
    return _scheduler.get_card_retrievability(card, _utc(at))


def explain_days(attempts: list[WordAttempt]) -> list[dict]:
    """Every review day as the model saw it: the day's answers, its grade
    and why, the chance of recall just before the day, and the state
    after it."""
    out = []
    card = Card()
    prev_first = None
    for day, day_attempts in _days(attempts).items():
        first = day_attempts[0].created_at
        r_before = _card_r(card, first) if prev_first is not None else None
        grade = day_grade(day_attempts)
        card, _ = _scheduler.review_card(card, grade, review_datetime=_utc(first))
        out.append(
            {
                "day": day,
                "first_at": first,
                "grade": GRADE_NAMES[grade],
                "reason": day_grade_reason(day_attempts),
                "recall_before": r_before,
                "days_since_previous": (first - prev_first).total_seconds() / 86400 if prev_first else None,
                "stability_after": card.stability,
                "difficulty_after": card.difficulty,
                "attempts": day_attempts,
            }
        )
        prev_first = first
    return out


def recall_curve(attempts: list[WordAttempt], until: datetime, max_points: int = 120) -> list[dict]:
    """R day by day (end of each Dushanbe day) from the first review up to
    `until` -- the forgetting curve, with the jumps the reviews made."""
    from datetime import timedelta

    days = list(_days(attempts).items())
    if not days:
        return []
    start = days[0][1][0].created_at.astimezone(DUSHANBE_TZ).replace(hour=23, minute=59, second=0, microsecond=0)
    total = max(0, (until.astimezone(DUSHANBE_TZ) - start).days + 1)
    step = max(1, -(-total // max_points))
    points = []
    t = start
    while t <= until.astimezone(DUSHANBE_TZ) + timedelta(days=step):
        at = min(t, until.astimezone(DUSHANBE_TZ))
        card, count = replay(attempts, until=at)
        if card is not None:
            points.append({"at": at, "recall": _card_r(card, at)})
        if at >= until.astimezone(DUSHANBE_TZ):
            break
        t += timedelta(days=step)
    return points


def falls_below_at(progress: WordProgress, target: float) -> datetime | None:
    """When this pair's recall drops below `target` (it decays steadily
    until the next review)."""
    from datetime import timedelta

    if progress.memory_stability is None or progress.memory_last_review is None:
        return None
    card = Card(
        state=State.Review,
        stability=progress.memory_stability,
        difficulty=progress.memory_difficulty,
        last_review=_utc(progress.memory_last_review),
    )
    lo, hi = 0.0, 3650.0
    start = _utc(progress.memory_last_review)
    if _card_r(card, start + timedelta(days=hi)) >= target:
        return None
    for _ in range(40):
        mid = (lo + hi) / 2
        if _card_r(card, start + timedelta(days=mid)) >= target:
            lo = mid
        else:
            hi = mid
    return start + timedelta(days=hi)
