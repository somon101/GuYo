from datetime import timedelta

import pytest

from app.models.duel import Duel
from app.models.friendship import Friendship
from app.progress.stats import week_start
from app.core.dates import dushanbe_today
from app.seasonpass import duels, service


def _friends(db, a, b):
    db.add(Friendship(user_id=a.id, friend_id=b.id))
    db.add(Friendship(user_id=b.id, friend_id=a.id))
    db.commit()


def test_challenge_accept_and_winner_gets_bonus(db, make_user, active_season):
    a, b, stranger = make_user(), make_user(), make_user()
    _friends(db, a, b)
    with pytest.raises(duels.DuelError):
        duels.challenge(db, a, stranger.id)  # only friends
    db.rollback()
    duel = duels.challenge(db, a, b.id)
    db.commit()
    with pytest.raises(duels.DuelError):
        duels.challenge(db, b, a.id)  # one duel a week
    db.rollback()
    with pytest.raises(duels.DuelError):
        duels.accept(db, a, duel.id)  # only the opponent accepts
    db.rollback()
    duels.accept(db, b, duel.id)
    service.award_xp(db, a, "word", "x1", 40)
    service.award_xp(db, b, "word", "x2", 10)
    db.commit()
    assert duels.scores(db, duel) == (40, 10)
    assert duels.state(db, a)["current"]["my_xp"] == 40

    next_week = week_start(dushanbe_today()) + timedelta(days=7)
    assert duels.finish_due(db, next_week) == 1
    db.commit()
    db.refresh(duel)
    assert duel.winner_id == a.id and duel.status == "finished"
    assert service.total_xp(db, a.id, active_season.id) == 40 + service.get_pass_settings(db).xp_duel_win
    assert duels.finish_due(db, next_week) == 0  # closed once


def test_decline_and_http(client, db, make_user, auth, active_season):
    a, b = make_user(), make_user()
    _friends(db, a, b)
    r = client.post("/duels", json={"friend_id": b.id}, headers=auth(a))
    assert r.status_code == 200 and r.json()["current"]["status"] == "pending"
    duel_id = r.json()["current"]["id"]
    r = client.post(f"/duels/{duel_id}/decline", headers=auth(b))
    assert r.status_code == 200 and r.json()["current"] is None
    assert db.get(Duel, duel_id).status == "declined"
    assert client.post("/duels", json={"friend_id": 424242}, headers=auth(a)).status_code == 409
