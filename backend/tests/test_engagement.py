from datetime import timedelta

from app.achievements.streak import record_activity
from app.core.dates import dushanbe_today
from app.models.achievement import UserActivityDay
from app.models.season_pass import PassXpEvent
from app.notifications.reminders import render


def test_comeback_bonus_only_after_a_break(db, make_user, active_season):
    user = make_user()
    db.add(UserActivityDay(user_id=user.id, activity_date=dushanbe_today() - timedelta(days=5)))
    db.commit()
    assert record_activity(db, user)
    db.commit()
    sources = {e.source for e in db.query(PassXpEvent).filter_by(user_id=user.id)}
    assert "comeback" in sources

    other = make_user()
    db.add(UserActivityDay(user_id=other.id, activity_date=dushanbe_today() - timedelta(days=1)))
    db.commit()
    record_activity(db, other)
    db.commit()
    assert "comeback" not in {e.source for e in db.query(PassXpEvent).filter_by(user_id=other.id)}


def test_reminder_text_gets_the_word_count():
    assert render("У вас {слов} слов, серия {дни} дн.", 9, 12) == "У вас 12 слов, серия 9 дн."
    assert render("Серия {дни}", 3) == "Серия 3"
