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
