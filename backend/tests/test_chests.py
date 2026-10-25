import random
from datetime import datetime, timedelta, timezone

import pytest

from app.achievements.streak import record_activity
from app.chests import service
from app.models.chests import ChestType


@pytest.fixture(autouse=True)
def _restore_types(db):
    yield
    db.rollback()
    db.query(ChestType).filter_by(key="wood").update(
        {"name": "Деревянный сундук", "max_diamonds": 10, "max_freezes": 1, "max_merges": 1, "max_points": 20, "booster_minutes": 0}
    )
    db.commit()


def test_open_gives_one_prize_within_ceiling(db, make_user):
    user = make_user()
    wood = db.get(ChestType, "wood")
    seen = set()
    for i in range(60):
        chest = service.grant_chest(db, user, "wood", "admin", f"t{i}", force=True)
        opened = service.open_chest(db, user, chest.id, random.Random(i))
        cap = {"diamonds": wood.max_diamonds, "freeze": wood.max_freezes, "merge": wood.max_merges, "points": wood.max_points}[opened.prize_kind]
        assert 1 <= opened.prize_amount <= cap
        seen.add(opened.prize_kind)
    assert seen == {"diamonds", "freeze", "merge", "points"}
    again = service.open_chest(db, user, chest.id)  # a repeat is harmless: same prize, paid once
    assert (again.prize_kind, again.prize_amount) == (opened.prize_kind, opened.prize_amount)


def test_zero_ceiling_removes_prize_kind(db, make_user):
    user = make_user()
    wood = db.get(ChestType, "wood")
    wood.max_freezes = wood.max_merges = wood.max_points = 0
    db.commit()
    for i in range(10):
        c = service.grant_chest(db, user, "wood", "admin", f"z{i}", force=True)
        assert service.open_chest(db, user, c.id, random.Random(i)).prize_kind == "diamonds"


def test_prizes_are_credited(db, make_user):
    user = make_user()
    wood = db.get(ChestType, "wood")
    wood.max_freezes = wood.max_merges = wood.max_points = 0
    wood.max_diamonds = 1
    db.commit()
    c = service.grant_chest(db, user, "wood", "admin", "d", force=True)
    service.open_chest(db, user, c.id)
    db.commit()
    db.refresh(user)
    assert user.diamonds_balance == 1


def test_daily_needs_study_and_is_once_a_day(db, make_user):
    user = make_user()
    assert service.daily_state(db, user)["available"] is False
    with pytest.raises(service.ChestError):
        service.claim_daily(db, user)
    record_activity(db, user)
    db.commit()
    assert service.daily_state(db, user)["available"] is True
    service.claim_daily(db, user)
    db.commit()
    with pytest.raises(service.ChestError):
        service.claim_daily(db, user)


def test_bank_and_daily_cap_but_admin_ignores_them(db, make_user):
    user = make_user()
    s = service.get_settings(db)
    s.inventory_max = 2
    db.commit()
    assert service.grant_chest(db, user, "wood", "pass", "a")
    assert service.grant_chest(db, user, "wood", "pass", "b")
    assert service.grant_chest(db, user, "wood", "pass", "c") is None  # bank full
    assert service.grant_chest(db, user, "wood", "admin", "d", force=True)
    assert service.grant_chest(db, user, "wood", "pass", "a") is None  # same key twice


def test_pity_after_low_rolls_and_double(db, make_user):
    user = make_user()
    s = service.get_settings(db)
    s.pity_after = 2
    db.commit()
    wood = db.get(ChestType, "wood")
    wood.max_freezes = wood.max_merges = wood.max_points = 0
    wood.max_diamonds = 100
    db.commit()

    class Low(random.Random):
        def randint(self, a, b):
            return a

    for i in range(2):
        c = service.grant_chest(db, user, "wood", "admin", f"p{i}", force=True)
        assert service.open_chest(db, user, c.id, Low()).prize_amount == 1
    c = service.grant_chest(db, user, "wood", "admin", "p2", force=True)
    assert service.open_chest(db, user, c.id, Low()).prize_amount >= 50  # guaranteed
    s.double_until = datetime.now(timezone.utc) + timedelta(hours=1)
    s.pity_after = 0
    c = service.grant_chest(db, user, "wood", "admin", "p3", force=True)
    assert service.open_chest(db, user, c.id, Low()).prize_amount == 2


def test_api_flow_and_admin_send(client, db, make_user, admin_headers, auth):
    user = make_user(login="somon")
    r = client.post("/admin/chests/send", headers=admin_headers, json={"user": "somon", "chest_key": "gold", "count": 2})
    assert r.status_code == 200 and r.json()["bank"] == 2
    client.post("/admin/chests/send", headers=admin_headers, json={"user": "somon", "chest_key": "gold"})
    st = client.get("/chests", headers=auth(user)).json()
    assert len(st["chests"]) == 3 and len(st["types"]) == 4
    opened = client.post(f"/chests/{st['chests'][0]['id']}/open", headers=auth(user)).json()
    assert opened["kind"] in ("diamonds", "freeze", "merge", "points") and len(opened["state"]["chests"]) == 2
    assert client.post("/admin/chests/send", headers=admin_headers, json={"user": "nobody", "chest_key": "gold"}).status_code == 404
    assert client.get("/admin/chests", headers=admin_headers).json()["stats"]["granted"]
    r = client.put("/admin/chests/settings", headers=admin_headers, json={
        "daily_enabled": True, "daily_chest_key": "purple", "daily_requires_activity": False,
        "daily_conditions": "x", "inventory_max": 5, "daily_cap": 5, "pity_after": 0, "double_hours": 2})
    assert r.json()["double_until"]
    r = client.post("/chests/daily/claim", headers=auth(user))
    assert r.status_code == 200


def test_streak_comeback_duel_and_pass_chests(db, make_user, active_season):
    from app.models.chests import UserChest
    from app.chests import rewards
    from app.seasonpass.service import _give

    user = make_user()
    rewards.give(db, user, rewards.get_rule(db, "streak_7"), "streak", "streak7:x")
    rewards.give(db, user, rewards.get_rule(db, "streak_7"), "streak", "streak7:x")  # same milestone: once
    assert db.query(UserChest).filter_by(user_id=user.id, source="streak").count() == 1
    given = rewards.give(db, user, rewards.get_rule(db, "comeback"), "comeback", "c:1")
    assert given["xp"] == 20 and given["chests"] == ["wood"]
    _give(db, user, {"type": "chest", "amount": 1, "key": "purple"}, "n", active_season, ref="free:2")
    assert db.query(UserChest).filter_by(user_id=user.id, chest_key="purple", source="pass").count() == 1
    assert rewards.validate_rewards(db, [{"type": "diamonds", "amount": 3}])


def test_open_many_one_kind_all_or_nothing(client, db, make_user, auth):
    user = make_user()
    for i in range(7):
        service.grant_chest(db, user, "wood", "admin", f"m{i}", force=True)
    service.grant_chest(db, user, "gold", "admin", "g", force=True)
    db.commit()
    h = auth(user)
    r = client.post("/chests/open-many", headers=h, json={"chest_key": "wood", "count": 5})
    assert r.status_code == 200 and len(r.json()["prizes"]) == 5
    assert sum(1 for c in r.json()["state"]["chests"] if c["chest_key"] == "wood") == 2
    assert client.post("/chests/open-many", headers=h, json={"chest_key": "wood", "count": 5}).status_code == 409
    assert client.post("/chests/open-many", headers=h, json={"chest_key": "wood", "count": 3}).status_code == 409
    assert client.post("/chests/open-many", headers=h, json={"chest_key": "gold", "count": 1}).status_code == 200


def test_prizes_are_sealed_in_the_bank_and_opening_is_idempotent(client, db, make_user, auth):
    user = make_user()
    for i in range(3):
        service.grant_chest(db, user, "wood", "admin", f"s{i}", force=True)
    db.commit()
    h = auth(user)
    bank = client.get("/chests", headers=h).json()["chests"]
    assert len(bank) == 3 and all(c["prize_kind"] and c["prize_amount"] >= 1 for c in bank)
    assert client.get("/chests", headers=h).json()["chests"] == bank  # the same prizes every time
    ids = [c["id"] for c in bank[:2]]
    first = client.post("/chests/open-ids", headers=h, json={"ids": ids}).json()
    assert [p["kind"] for p in first["prizes"]] == [c["prize_kind"] for c in bank[:2]]
    balance = first["diamonds"]
    again = client.post("/chests/open-ids", headers=h, json={"ids": ids}).json()  # a retry pays nothing
    assert again["diamonds"] == balance and len(again["state"]["chests"]) == 1


def test_booster_doubles_chest_prizes_only_while_it_runs(client, db, make_user, auth, admin_headers):
    from app.chests import boosters

    user = make_user(login="boost")
    wood = db.get(ChestType, "wood")
    wood.max_freezes = wood.max_merges = wood.max_points = 0
    wood.max_diamonds = 1
    db.commit()
    h = auth(user)
    # held ticket, then switched on by hand
    assert client.post("/admin/chests/send-booster", headers=admin_headers, json={"user": "boost", "minutes": 30, "count": 2}).status_code == 200
    st = client.get("/boosters", headers=h).json()
    assert {i["minutes"]: i["qty"] for i in st["items"]}[30] == 2 and st["active_until"] is None
    for i in range(3):
        service.grant_chest(db, user, "wood", "admin", f"b{i}", force=True)
    db.commit()
    ids = [c["id"] for c in client.get("/chests", headers=h).json()["chests"]]
    first = client.post("/chests/open-ids", headers=h, json={"ids": ids[:1]}).json()
    assert first["prizes"][0]["amount"] == 1 and first["prizes"][0]["doubled"] is False  # no ticket: plain
    assert client.post("/boosters/activate", headers=h, json={"minutes": 30}).status_code == 200
    second = client.post("/chests/open-ids", headers=h, json={"ids": ids[1:2]}).json()
    assert second["prizes"][0]["amount"] == 2 and second["prizes"][0]["doubled"] is True  # ticket on: doubled
    # a second ticket adds its time to the running one
    before = client.get("/boosters", headers=h).json()["seconds_left"]
    client.post("/boosters/activate", headers=h, json={"minutes": 30})
    assert client.get("/boosters", headers=h).json()["seconds_left"] > before + 1700
    assert client.post("/boosters/activate", headers=h, json={"minutes": 30}).status_code == 409  # none left


def test_a_chest_opened_offline_is_judged_by_when_it_was_opened(client, db, make_user, auth):
    from datetime import datetime, timedelta, timezone

    from app.chests import boosters

    user = make_user()
    wood = db.get(ChestType, "wood")
    wood.max_freezes = wood.max_merges = wood.max_points = 0
    wood.max_diamonds = 1
    db.commit()
    boosters.add_booster(db, user, 30)
    boosters.activate(db, user, 30)
    c = service.grant_chest(db, user, "wood", "admin", "o", force=True)
    db.commit()
    h = auth(user)
    client.get("/chests", headers=h)
    long_ago = (datetime.now(timezone.utc) - timedelta(hours=2)).isoformat()
    out = client.post("/chests/open-ids", headers=h, json={"items": [{"id": c.id, "opened_at": long_ago}]}).json()
    assert out["prizes"][0]["doubled"] is False  # it was opened before the ticket was on


def test_booster_is_a_reward_and_a_chest_prize(db, make_user):
    from app.chests import boosters, rewards

    user = make_user()
    assert rewards.validate_rewards(db, [{"type": "booster", "amount": 60}]) == [{"type": "booster", "amount": 60}]
    given = rewards.give(db, user, [{"type": "booster", "amount": 60}], "duel", "d:1")
    assert given["boosters"] == [60]
    assert rewards.give(db, user, [{"type": "booster", "amount": 60}], "duel", "d:1")["boosters"] == []  # once
    wood = db.get(ChestType, "wood")
    wood.max_diamonds = wood.max_freezes = wood.max_merges = wood.max_points = 0
    wood.booster_minutes = 1440
    db.commit()
    c = service.grant_chest(db, user, "wood", "admin", "bp", force=True)
    opened = service.open_chest(db, user, c.id)
    assert (opened.prize_kind, opened.prize_amount, opened.doubled) == ("booster", 1440, False)
    held = {i["minutes"]: i["qty"] for i in boosters.state(db, user)["items"]}
    assert held[60] == 1 and held[1440] == 1
