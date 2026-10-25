import pytest

from app.seasonpass import service, teams
from app.seasonpass.service import PassError


def test_xp_is_awarded_once_per_key(db, make_user, active_season):
    user = make_user()
    assert service.award_xp(db, user, "word", "w1", 10) == 10
    assert service.award_xp(db, user, "word", "w1", 10) == 0
    db.commit()
    assert service.total_xp(db, user.id, active_season.id) == 10


def test_no_xp_without_active_season(db, make_user):
    assert service.award_xp(db, make_user(), "word", "w1", 10) == 0


def test_level_reward_needs_level_and_is_taken_once(db, make_user, active_season):
    user = make_user()
    with pytest.raises(PassError):
        service.claim_level(db, user, 2, "free")  # not reached yet
    db.rollback()
    service.award_xp(db, user, "word", "big", 100_000)
    db.commit()
    service.claim_level(db, user, 1, "free")
    db.commit()
    with pytest.raises(PassError):
        service.claim_level(db, user, 1, "free")  # already taken
    db.rollback()


def test_premium_lane_requires_premium(db, make_user, active_season):
    user = make_user()
    service.award_xp(db, user, "word", "big", 100_000)
    db.commit()
    levels = service.season_pass(db, active_season).definition["levels"]
    lv = next(x["level"] for x in levels if x.get("premium"))
    with pytest.raises(PassError):
        service.claim_level(db, user, lv, "premium")
    db.rollback()


def test_pass_endpoint_and_claim_http(client, db, make_user, auth, active_season):
    user = make_user()
    assert client.get("/season-pass", headers=auth(user)).status_code == 200
    r = client.post("/season-pass/claim", json={"level": 5, "track": "free"}, headers=auth(user))
    assert r.status_code in (400, 409)


def test_team_create_invite_accept_and_one_team_per_user(db, make_user):
    owner, friend = make_user(), make_user()
    team = teams.create_team(db, owner, "Alpha", True)
    with pytest.raises(teams.TeamError):
        teams.create_team(db, owner, "Beta", True)
    db.commit()
    with pytest.raises(teams.TeamError):
        teams.accept_invite(db, friend, team.id)  # no invitation
    db.rollback()
    teams.join_open(db, friend, team.id)
    db.commit()
    assert len(teams.members_of(db, team)) == 2


def test_admin_economy(client, db, make_user, admin_headers, active_season):
    a, b = make_user(), make_user()
    service.award_xp(db, a, "word", "k1", 100)
    service.award_xp(db, b, "lesson", "k2", 30)
    db.commit()
    r = client.get("/admin/season-pass/economy", headers=admin_headers).json()
    assert r["players"] == 2 and r["total_xp"] == 130
    assert {x["source"] for x in r["xp_by_source"]} == {"word", "lesson"}
    assert sum(x["people"] for x in r["level_distribution"]) == 2


def test_pass_gives_diamonds_once(db, make_user, active_season):
    user = make_user()
    sp = service.season_pass(db, active_season)
    first = sp.definition["levels"][0]
    assert first["free"]["type"] == "diamonds"  # the default template starts with a gift
    service.award_xp(db, user, "word", "big", 100_000)
    db.commit()
    service.claim_level(db, user, 1, "free")
    db.commit()
    db.refresh(user)
    assert user.diamonds_balance == first["free"]["amount"]
    with pytest.raises(PassError):
        service.claim_level(db, user, 1, "free")
    db.rollback()
    db.refresh(user)
    assert user.diamonds_balance == first["free"]["amount"]


def test_diamonds_reward_is_validated(db):
    assert service._reward({"type": "diamonds", "amount": 15}, 1) == {"type": "diamonds", "amount": 15}
    with pytest.raises(PassError):
        service._reward({"type": "diamonds", "amount": 0}, 1)


def test_admin_grants_pass_xp(client, db, make_user, admin_headers, active_season):
    user = make_user("xpuser")
    r = client.post("/admin/season-pass/grant-xp", headers=admin_headers, json={"user": "xpuser", "amount": 5000})
    assert r.status_code == 200
    assert r.json()["xp"] == 5000 and r.json()["level"] >= 1
    r = client.post("/admin/season-pass/grant-xp", headers=admin_headers, json={"user": "nobody", "amount": 5})
    assert r.status_code == 404


def test_admin_showcase_is_read_only(client, db, make_user, admin_headers):
    from app.models.season_pass import UserCosmetic

    user = make_user("showme")
    db.add(UserCosmetic(user_id=user.id, kind="frame", key="ocean", label="Океан"))
    db.commit()
    r = client.get("/admin/season-pass/showcase", headers=admin_headers, params={"user": "showme"})
    assert r.status_code == 200
    body = r.json()
    assert body["login"] == "showme" and body["collection"]["frames"][0]["key"] == "ocean"
    assert client.get("/admin/season-pass/showcase", headers=admin_headers, params={"user": "zzz"}).status_code == 404
