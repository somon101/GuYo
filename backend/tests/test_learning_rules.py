"""Rules that were checked by hand-run scripts before: the "learned" rule,
streak freezes, wearing badges, and personal auto-quests."""

from datetime import timedelta

from app.achievements import record_activity
from app.achievements.conditions import streak_with_freezes
from app.core.dates import dushanbe_today, utc_now
from app.memory import recall_probability
from app.models.achievement import UserActivityDay, UserStreakFreeze
from app.models.quest import Quest, QuestWord
from app.models.word import Word
from app.models.word_attempt import WordAttempt
from app.models.word_progress import WordProgress
from app.priority import maybe_create_personal_quests
from app.seasonpass import cosmetics, service


def _words(db, dictionary):
    return db.query(Word).filter(Word.dictionary_id == dictionary.id).order_by(Word.id).all()


def test_learned_needs_recall_exercises_right_at_the_end(client, db, make_user, auth, make_dictionary):
    d = make_dictionary(16)
    user = make_user()
    h = auth(user)
    lesson = client.post("/lessons", headers=h, json={"dictionary_id": d.id, "random_count": 4}).json()
    lid, ex = lesson["id"], lesson["exercise_keys"]
    w0, w1, w2, w3 = [w["word_id"] for w in lesson["words"]]
    client.post(f"/lessons/{lid}/pass", headers=h)

    def answer(key, word, ok):
        r = client.post(
            f"/lessons/{lid}/exercises/{key}/answers",
            headers=h,
            json={"word_id": word, "is_correct": ok, "duration_ms": 2000, "deferred": True},
        )
        assert r.status_code == 200, r.text

    recall = [e for e in ex if e in ("build_word", "speaking_word")]
    for e in ex:
        for w in (w0, w1, w2, w3):
            answer(e, w, True)
    answer(recall[0], w1, False)  # wrong in a recall exercise, last: not learned
    answer(recall[0], w2, False)
    answer(recall[0], w2, True)  # wrong, then corrected: learned
    done = client.post(f"/lessons/{lid}/pass/finish", headers=h).json()
    learned = {w["word_id"]: w["is_learned"] for w in done["words"]}
    assert learned[w0] and learned[w2] and learned[w3]
    assert not learned[w1]
    assert done["is_completed"] is False

    # The repeat pass holds only the word that is not learned yet.
    client.post(f"/lessons/{lid}/pass", headers=h)
    for e in ex:
        answer(e, w1, True)
    assert client.post(f"/lessons/{lid}/pass/finish", headers=h).json()["is_completed"] is True


def _person(db, make_user, active_offsets, freezes):
    user = make_user(streak_freezes=freezes)
    today = dushanbe_today()
    for o in active_offsets:
        db.add(UserActivityDay(user_id=user.id, activity_date=today - timedelta(days=o)))
    db.commit()
    return user


def test_freezes_bridge_a_long_gap_but_only_if_there_are_enough(db, make_user):
    gap = range(5, 11)  # active 10..5 days ago, missed 4..1
    rich = _person(db, make_user, gap, 3)
    record_activity(db, rich)
    db.commit()
    db.refresh(rich)
    streak, _ = streak_with_freezes(db, rich)
    assert streak >= 7 and rich.streak_freezes == 0
    assert db.query(UserStreakFreeze).filter_by(user_id=rich.id).count() == 3

    poor = _person(db, make_user, gap, 2)  # 4 missed days need 3 freezes
    record_activity(db, poor)
    db.commit()
    db.refresh(poor)
    assert poor.streak_freezes == 2  # not enough: nothing is spent
    assert streak_with_freezes(db, poor)[0] == 1

    none = _person(db, make_user, gap, 0)
    record_activity(db, none)
    db.commit()
    assert streak_with_freezes(db, none)[0] == 1


def test_one_missed_day_is_forgiven_without_a_freeze(db, make_user):
    user = _person(db, make_user, range(2, 8), 2)  # missed only yesterday
    record_activity(db, user)
    db.commit()
    db.refresh(user)
    assert user.streak_freezes == 2
    assert streak_with_freezes(db, user)[0] >= 7


def test_badges_and_titles_are_worn_one_of_each(db, make_user, active_season):
    user = make_user()
    badge = cosmetics.grant(db, user, {"type": "badge", "key": "crown", "text": "Корона"}, active_season)
    title = cosmetics.grant(db, user, {"type": "title", "text": "Знаток"}, active_season)
    again = cosmetics.grant(db, user, {"type": "badge", "key": "crown", "text": "Корона"}, active_season)
    db.commit()
    assert again.id == badge.id  # granted once
    assert user.equipped_badge_id == badge.id and user.equipped_title_id == title.id
    cosmetics.equip(db, user, None, title.id)
    assert user.equipped_badge_id is None
    other = make_user()
    try:
        cosmetics.equip(db, other, badge.id, None)  # not theirs
        raise AssertionError("must refuse")
    except cosmetics.CosmeticError:
        pass


def test_auto_quests_one_per_weak_exercise_and_no_word_twice(db, make_user, make_dictionary):
    from app.premium import get_premium_settings

    get_premium_settings(db).premium_enabled = False
    d = make_dictionary(16)
    ws = _words(db, d)
    user = make_user()
    now = utc_now()

    def fit(p):
        p.memory_stability = 10.0
        for t in range(1, 60):
            p.memory_last_review = now - timedelta(days=t)
            r = recall_probability(p, now)
            if r is not None and 0.72 < r < 0.84:
                return

    def weak(group, exercise):
        for w in group:
            p = WordProgress(user_id=user.id, word_id=w.id, memory_difficulty=5.0)
            db.add(p)
            db.flush()
            fit(p)
            for ok in (False, False, True):
                db.add(
                    WordAttempt(
                        user_id=user.id, word_id=w.id, exercise_key=exercise, is_correct=ok, source="lesson",
                        created_at=now - timedelta(days=1),
                    )
                )

    for w in ws[:2]:
        db.add(WordProgress(user_id=user.id, word_id=w.id, mastered_at=now))
    weak(ws[2:6], "speaking_word")
    weak(ws[6:9], "matching")
    db.commit()

    first = maybe_create_personal_quests(db, user, d.id)
    db.commit()
    assert {q.exercise_key for q in first} == {"speaking_word", "matching"}
    ids = [w for q in first for (w,) in db.query(QuestWord.word_id).filter_by(quest_id=q.id)]
    assert len(ids) == len(set(ids))
    assert maybe_create_personal_quests(db, user, d.id) == []  # nothing new to cover

    weak(ws[9:12], "matching")
    db.commit()
    assert len(maybe_create_personal_quests(db, user, d.id)) >= 1
    assert db.query(Quest).filter_by(owner_user_id=user.id).count() >= 3
