from app.models.notification import Notification
from app.seasonpass import reminders, service


def _sent(db, user):
    return db.query(Notification).filter(Notification.user_id == user.id, Notification.dedupe_key.like("pass_reminder:%")).count()


def test_reward_waiting_is_sent_once_in_a_window(db, make_user, active_season):
    user = make_user(ui_language="en")
    service.award_xp(db, user, "word", "k", 100_000)
    db.commit()
    assert reminders.send_pass_reminders(db, 12, 10) >= 1
    db.commit()
    before = _sent(db, user)
    assert reminders.send_pass_reminders(db, 12, 10) == 0  # same window: no repeat
    assert _sent(db, user) == before


def test_quiet_hours_and_no_xp_send_nothing(db, make_user, active_season):
    user, other = make_user(), make_user()
    service.award_xp(db, user, "word", "k", 100_000)
    db.commit()
    assert reminders.send_pass_reminders(db, 23, 10) == 0  # too late
    assert reminders.send_pass_reminders(db, 8, 10) == 0  # too early
    assert _sent(db, other) == 0


def test_switch_off(db, make_user, active_season):
    user = make_user()
    service.award_xp(db, user, "word", "k", 100_000)
    service.get_pass_settings(db).reminders_enabled = False
    db.commit()
    assert reminders.send_pass_reminders(db, 12, 10) == 0


def test_summary_of_finished_season_and_one_notification(client, db, make_user, auth, active_season):
    from datetime import timedelta

    from app.core.dates import utc_now

    user = make_user(ui_language="en")
    service.award_xp(db, user, "word", "k", 250)
    active_season.status = "completed"
    active_season.ends_at = utc_now() - timedelta(hours=1)
    active_season.starts_at = utc_now() - timedelta(days=30)
    db.commit()
    r = client.get("/season-pass/summary", headers=auth(user))
    assert r.status_code == 200
    body = r.json()
    assert body["xp"] == 250 and body["level"] >= 1
    assert reminders.send_season_summaries(db) == 1
    db.commit()
    assert reminders.send_season_summaries(db) == 0  # only once
    assert client.get("/season-pass/summary", headers=auth(make_user())).json() is None
