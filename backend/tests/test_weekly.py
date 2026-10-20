from datetime import date, datetime, timedelta

from app.core.dates import DUSHANBE_TZ, dushanbe_today
from app.models.achievement import UserActivityDay
from app.models.notification import Notification
from app.models.word_progress import WordProgress
from app.notifications.weekly import message, send_weekly_digests
from app.progress.stats import week_numbers, week_start, weekly_series


def _learn(db, user, word, when):
    db.add(WordProgress(user_id=user.id, word_id=word.id, mastered_at=when))


def test_week_numbers_and_series(db, make_user, make_dictionary):
    from app.models.word import Word

    d = make_dictionary(4)
    words = db.query(Word).filter(Word.dictionary_id == d.id).all()
    user = make_user()
    monday = week_start(dushanbe_today())
    noon = datetime.combine(monday, datetime.min.time(), tzinfo=DUSHANBE_TZ) + timedelta(hours=12)
    _learn(db, user, words[0], noon)
    _learn(db, user, words[1], noon + timedelta(days=1))
    _learn(db, user, words[2], noon - timedelta(days=3))  # last week
    db.add(UserActivityDay(user_id=user.id, activity_date=monday))
    db.commit()
    assert week_numbers(db, user.id, monday) == {"week_start": monday, "words": 2, "active_days": 1}
    assert week_numbers(db, user.id, monday - timedelta(weeks=1))["words"] == 1
    series = weekly_series(db, user.id, 4)
    assert len(series) == 4
    assert series[-1]["week_start"] == week_start(dushanbe_today())
    assert series[-2]["words"] == 1


def test_digest_text_compares_with_last_week():
    assert "больше" in message("ru", 9, 4, 5)[1]
    assert "fewer" in message("en", 2, 1, 5)[1]
    assert "(" not in message("en", 3, 1, 3)[1]


def test_digest_once_on_sunday_to_active_only(db, make_user):
    user, idle = make_user(), make_user()
    sunday = date(2026, 10, 25)  # a Sunday
    db.add(UserActivityDay(user_id=user.id, activity_date=sunday))
    db.commit()
    assert send_weekly_digests(db, sunday, 12, 10, True) == 1
    db.commit()
    assert send_weekly_digests(db, sunday, 12, 10, True) == 0  # once a week
    assert send_weekly_digests(db, date(2026, 10, 24), 12, 10, True) == 0  # not Sunday
    assert db.query(Notification).filter(Notification.user_id == idle.id).count() == 0


def test_progress_endpoint(client, make_user, auth):
    r = client.get("/users/me/progress", headers=auth(make_user()))
    assert r.status_code == 200
    body = r.json()
    assert body["total_words"] == 0 and len(body["weeks"]) == 12
