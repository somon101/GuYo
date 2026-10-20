from app.core.security import create_access_token


def test_logout_all_ends_other_devices_but_not_this_one(client, db, make_user, auth):
    user = make_user()
    old = auth(user)
    assert client.get("/users/me/profile", headers=old).status_code == 200
    r = client.post("/auth/logout-all", headers=old)
    assert r.status_code == 200
    assert client.get("/users/me/profile", headers=old).status_code == 401
    fresh = {**old, "Authorization": f"Bearer {r.json()['access_token']}"}
    assert client.get("/users/me/profile", headers=fresh).status_code == 200


def test_token_without_version_still_works(client, make_user, auth):
    from jose import jwt
    from app.config import get_settings

    user = make_user()
    s = get_settings()
    token = jwt.encode({"sub": str(user.id), "role": "user", "exp": 4102444800}, s.jwt_secret, algorithm=s.jwt_algorithm)
    assert client.get("/users/me/profile", headers={"Authorization": f"Bearer {token}", "X-App-Build": "99999"}).status_code == 200


def test_server_messages_follow_ui_language(client, make_user, auth):
    user = make_user()
    r = client.post("/season-pass/claim", json={"level": 1, "track": "free"}, headers={**auth(user), "X-UI-Language": "en"})
    assert r.json()["detail"] == "There is no active season right now"
    r = client.post("/season-pass/claim", json={"level": 1, "track": "free"}, headers=auth(user))
    assert r.json()["detail"] == "Сейчас нет активного сезона"
