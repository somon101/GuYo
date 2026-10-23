import random

import pytest

from app.achievements.streak import record_activity
from app.seasonpass import chest, service


def test_chest_needs_study_opens_once_and_pays(db, make_user, active_season):
    user = make_user()
    assert chest.state(db, user)["available"] is False  # nothing studied yet
    with pytest.raises(chest.ChestError):
        chest.open_chest(db, user)
    db.rollback()
    record_activity(db, user)
    db.commit()
    assert chest.state(db, user)["available"] is True
    rng = random.Random(1)
    opened = chest.open_chest(db, user, rng)
    db.commit()
    assert opened.kind in ("diamonds", "freeze")
    if opened.kind == "diamonds":
        db.refresh(user)
        assert user.diamonds_balance == opened.amount
    with pytest.raises(chest.ChestError):
        chest.open_chest(db, user, rng)  # once a day
    db.rollback()
    assert chest.state(db, user)["available"] is False


def test_freeze_roll_respects_the_cap(db, make_user, active_season):
    user = make_user(streak_freezes=3)  # at the default cap
    record_activity(db, user)
    s = service.get_pass_settings(db)
    s.chest_freeze_chance = 100
    db.commit()
    assert chest.open_chest(db, user).kind == "diamonds"


def test_chest_http(client, db, make_user, auth, active_season):
    user = make_user()
    h = auth(user)
    assert client.post("/chest/open", headers=h).status_code == 409
    record_activity(db, user)
    db.commit()
    assert client.get("/chest", headers=h).json()["available"] is True
    r = client.post("/chest/open", headers=h)
    assert r.status_code == 200 and r.json()["opened"] is not None
