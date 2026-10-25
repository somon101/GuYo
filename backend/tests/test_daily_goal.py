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
    assert r["completed"] and r["just_completed"] and r["xp"] > 0
    r = client.get("/daily-goal", headers=h).json()
    assert r["completed"] and not r["just_completed"]  # XP only once a day


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
