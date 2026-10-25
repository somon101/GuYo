from app.models.word_attempt import WordAttempt


def _answer(db, user, word, n=1):
    for _ in range(n):
        db.add(WordAttempt(user_id=user.id, word_id=word.id, exercise_key="choose", is_correct=True))
    db.commit()


def test_goal_counts_distinct_words_and_celebrates_once(client, db, make_user, auth, make_dictionary, active_season):

    user = make_user()
    from app.models.word import Word

    d = make_dictionary(8)
    words = db.query(Word).filter(Word.dictionary_id == d.id).all()
    h = auth(user)
    assert client.put("/daily-goal", json={"goal": 5}, headers=h).json()["goal"] == 5
    for w in words[:4]:
        _answer(db, user, w, n=3)  # repeats of one word count once
    r = client.get("/daily-goal", headers=h).json()
    assert (r["done"], r["completed"], r["just_completed"]) == (4, False, False)
    _answer(db, user, words[4])
    r = client.get("/daily-goal", headers=h).json()
    assert r["completed"] and r["just_completed"] and r["reward_ready"] and r["claim_id"]
    assert client.get("/daily-goal", headers=h).json()["just_completed"] is False  # earned once a day
    # nothing was paid by itself:
    from app.seasonpass import service as pass_service
    assert pass_service.total_xp(db, user.id, active_season.id) == 0
    out = client.post("/daily-goal/claim", json={"claim_id": r["claim_id"]}, headers=h).json()
    assert out["xp"] > 0 and out["state"]["reward_ready"] is False
    assert pass_service.total_xp(db, user.id, active_season.id) == out["xp"]
    assert client.post("/daily-goal/claim", json={"claim_id": r["claim_id"]}, headers=h).status_code == 409  # paid once


def test_unclaimed_reward_goes_to_notifications_with_a_button(client, db, make_user, auth, make_dictionary, active_season):
    from datetime import timedelta
    from app.chests import rewards
    from app.core.dates import dushanbe_today
    from app.models.chests import DailyGoalClaim
    from app.models.notification import Notification
    from app.models.word import Word

    user = make_user()
    words = db.query(Word).filter(Word.dictionary_id == make_dictionary(8).id).all()
    h = auth(user)
    client.put("/daily-goal", json={"goal": 5}, headers=h)
    for w in words[:5]:
        _answer(db, user, w)
    claim_id = client.get("/daily-goal", headers=h).json()["claim_id"]
    claim = db.get(DailyGoalClaim, claim_id)
    claim.day = dushanbe_today() - timedelta(days=1)  # it was earned yesterday and never taken
    db.commit()
    assert rewards.notify_unclaimed(db, dushanbe_today()) == 1
    assert rewards.notify_unclaimed(db, dushanbe_today()) == 0  # once
    db.commit()
    n = db.query(Notification).filter_by(user_id=user.id, source="goal_reward").one()
    assert n.action == f"claim_goal:{claim_id}" and n.payload
    listed = client.get("/notifications", headers=h).json()["items"][0]
    assert listed["action"] == f"claim_goal:{claim_id}"
    assert client.post("/daily-goal/claim", json={"claim_id": claim_id}, headers=h).status_code == 200
    assert client.get("/notifications", headers=h).json()["items"][0]["action"] is None  # the button is spent


def test_goal_is_fixed_once_filled_until_tomorrow(client, db, make_user, auth, make_dictionary, active_season):
    from app.models.chests import UserChest
    from app.models.word import Word

    user = make_user()
    words = db.query(Word).filter(Word.dictionary_id == make_dictionary(12).id).all()
    h = auth(user)
    assert client.put("/daily-goal", json={"goal": 10}, headers=h).status_code == 200
    client.put("/daily-goal", json={"goal": 5}, headers=h)  # not filled yet: still free to change
    for w in words[:5]:
        _answer(db, user, w)
    r = client.get("/daily-goal", headers=h).json()
    assert r["completed"] and r["locked"] and r["just_completed"]
    again = client.put("/daily-goal", json={"goal": 10}, headers=h)
    assert again.status_code == 409  # filled: no second choice today
    assert client.get("/daily-goal", headers=h).json()["goal"] == 5
    assert not client.get("/daily-goal", headers=h).json()["just_completed"]  # paid once
    assert db.query(UserChest).filter_by(user_id=user.id).count() == 0  # the 5-word tier pays XP only


def test_admin_edits_options_and_rewards(client, db, make_user, auth, admin_headers):
    r = client.put("/admin/chests/rewards", headers=admin_headers, json={
        "daily_goal": [{"words": 3, "rewards": [{"type": "diamonds", "amount": 7}]}, {"words": 8, "rewards": []}],
        "duel_win": [{"type": "chest", "key": "gold", "amount": 1}],
    })
    assert r.status_code == 200
    user = make_user()
    out = client.get("/daily-goal", headers=auth(user)).json()
    assert out["options"] == [3, 8] and out["goal"] == 8
    bad = client.put("/admin/chests/rewards", headers=admin_headers, json={"duel_win": [{"type": "chest", "key": "nope"}]})
    assert bad.status_code == 422
