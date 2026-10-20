"""The word check before a lesson, and the pause between «Повторить сегодня» lists."""

from datetime import timedelta

from app.core.dates import utc_now
from app.memory.review_lists import STATUS_ACTIVE, STATUS_CLOSED, STATUS_QUEUED, _activate_next
from app.models.review_list import ReviewList
from app.models.word_progress import WordProgress
from app.notifications.reminders import get_reminder_settings


def _lesson(client, h, dictionary):
    return client.post("/lessons", headers=h, json={"dictionary_id": dictionary.id, "random_count": 4}).json()


def test_check_cards_have_the_right_word_among_options(client, make_user, auth, make_dictionary):
    d = make_dictionary(16)
    h = auth(make_user())
    lesson = _lesson(client, h, d)
    check = client.get(f"/lessons/{lesson['id']}/check", headers=h).json()
    assert check["enabled"] and len(check["items"]) == 4
    for item in check["items"]:
        assert len(item["options"]) == 4
        assert any(o["word_id"] == item["word_id"] for o in item["options"])


def test_self_rating_feeds_memory_but_never_marks_a_word_learned(client, db, make_user, auth, make_dictionary):
    d = make_dictionary(16)
    user = make_user()
    h = auth(user)
    lesson = _lesson(client, h, d)
    items = client.get(f"/lessons/{lesson['id']}/check", headers=h).json()["items"]
    easy, hard = items[0], items[1]
    for item, rating in ((easy, "easy"), (hard, "hard")):
        r = client.post(
            f"/lessons/{lesson['id']}/check/answers",
            headers=h,
            json={"word_id": item["word_id"], "picked_word_id": item["word_id"], "rating": rating},
        )
        assert r.status_code == 200 and r.json()["is_correct"] is True
    # A wrong pick is just a record: it does not feed memory.
    wrong = items[2]
    other = next(o for o in wrong["options"] if o["word_id"] != wrong["word_id"])
    r = client.post(
        f"/lessons/{lesson['id']}/check/answers",
        headers=h,
        json={"word_id": wrong["word_id"], "picked_word_id": other["word_id"]},
    )
    assert r.json()["is_correct"] is False

    def progress(word_id):
        return db.query(WordProgress).filter_by(user_id=user.id, word_id=word_id).first()

    db.expire_all()
    e, hd, wr = progress(easy["word_id"]), progress(hard["word_id"]), progress(wrong["word_id"])
    assert e.memory_stability > hd.memory_stability
    assert e.mastered_at is None and hd.mastered_at is None
    assert wr is None or wr.memory_stability is None


def test_the_check_can_be_switched_off_by_the_admin(client, make_user, auth, make_dictionary, admin_headers):
    d = make_dictionary(16)
    h = auth(make_user())
    lesson = _lesson(client, h, d)
    assert client.put("/learning-settings", headers=admin_headers, json={"check_enabled": False}).status_code == 200
    assert client.get(f"/lessons/{lesson['id']}/check", headers=h).json()["enabled"] is False


def _lists(db, user, closed_ago_hours):
    now = utc_now()
    closed = ReviewList(
        user_id=user.id, dictionary_id=1, status=STATUS_CLOSED, size=10, created_at=now - timedelta(days=1),
        closed_at=now - timedelta(hours=closed_ago_hours),
    )
    queued = ReviewList(user_id=user.id, dictionary_id=1, status=STATUS_QUEUED, size=10, created_at=now)
    db.add_all([closed, queued])
    db.flush()
    return queued


def test_next_review_list_waits_for_the_pause(db, make_user, make_dictionary):
    make_dictionary(1)
    user = make_user()
    queued = _lists(db, user, closed_ago_hours=1)
    get_reminder_settings(db).review_list_pause_hours = 12
    assert _activate_next(db, [queued]) is None  # one hour after the last list: too early
    assert queued.status == STATUS_QUEUED
    get_reminder_settings(db).review_list_pause_hours = 0
    assert _activate_next(db, [queued]).status == STATUS_ACTIVE  # no pause: at once


def test_next_review_list_opens_after_the_pause(db, make_user, make_dictionary):
    make_dictionary(1)
    user = make_user()
    queued = _lists(db, user, closed_ago_hours=13)
    get_reminder_settings(db).review_list_pause_hours = 12
    assert _activate_next(db, [queued]).status == STATUS_ACTIVE
