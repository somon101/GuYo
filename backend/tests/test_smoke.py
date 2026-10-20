def test_app_answers_and_database_is_migrated(client, db, make_user, auth):
    user = make_user()
    r = client.get("/users/me/profile", headers=auth(user))
    assert r.status_code == 200
    assert r.json()["login"] == user.login
