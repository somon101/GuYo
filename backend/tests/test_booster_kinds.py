from datetime import datetime, timedelta, timezone

from app.chests import boosters
from app.models.chests import BoosterUse
from app.rating import award_word_points_if_new, grant_rating_points
from app.rating.service import get_or_create_user_rating
from app.seasonpass import service


def _run(db, user, kind, minutes=30):
    now = datetime.now(timezone.utc)
    db.add(BoosterUse(user_id=user.id, kind=kind, starts_at=now - timedelta(minutes=1), ends_at=now + timedelta(minutes=minutes)))
    db.flush()


def test_rating_booster_doubles_every_rating_point(db, make_user):
    user = make_user()
    grant_rating_points(db, user, 10)
    assert get_or_create_user_rating(db, user.id).total_points == 10
    _run(db, user, "rating")
    grant_rating_points(db, user, 10)
    assert get_or_create_user_rating(db, user.id).total_points == 30
    grant_rating_points(db, user, 10, boost=False)  # an admin's hand adjustment is exact
    assert get_or_create_user_rating(db, user.id).total_points == 40


def test_xp_booster_doubles_pass_energy_but_not_the_admins_gift(db, make_user, active_season):
    user = make_user()
    assert service.award_xp(db, user, "word", "w1", 10) == 10
    _run(db, user, "xp")
    assert service.award_xp(db, user, "word", "w2", 10) == 20
    assert service.award_xp(db, user, "admin", "a1", 10) == 10
    # a rating ticket does not touch the pass
    other = make_user()
    _run(db, other, "rating")
    assert service.award_xp(db, other, "word", "w3", 10) == 10


def test_kinds_keep_their_own_time_and_stock(db, make_user):
    user = make_user()
    boosters.add_booster(db, user, 30, 2, kind="xp")
    boosters.add_booster(db, user, 30, 1, kind="rating")
    boosters.activate(db, user, 30, "xp")
    boosters.activate(db, user, 30, "xp")  # the second one adds its time
    state = boosters.state(db, user)
    assert state["kinds"]["xp"]["seconds_left"] > 3000
    assert state["kinds"]["rating"]["seconds_left"] == 0
    assert {i["minutes"]: i["qty"] for i in state["kinds"]["rating"]["items"]}[30] == 1
    assert state["active_until"] is None  # the chest kind keeps its old shape


def test_admin_sends_a_booster_of_each_kind(client, db, make_user, admin_headers):
    user = make_user("boosty")
    r = client.post("/admin/chests/send-booster", headers=admin_headers, json={"user": "boosty", "minutes": 60, "count": 2, "kind": "rating"})
    assert r.status_code == 200
    state = boosters.state(db, user)
    assert {i["minutes"]: i["qty"] for i in state["kinds"]["rating"]["items"]}[60] == 2
    assert {i["minutes"]: i["qty"] for i in state["kinds"]["chest"]["items"]}[60] == 0
    assert client.post("/admin/chests/send-booster", headers=admin_headers, json={"user": "boosty", "minutes": 60, "kind": "nope"}).status_code == 422
