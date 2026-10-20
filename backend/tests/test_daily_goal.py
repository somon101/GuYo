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
