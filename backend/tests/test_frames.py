from app.seasonpass import cosmetics, service


def test_frame_reward_is_validated_granted_and_worn(client, db, make_user, auth, active_season):
    user = make_user()
    reward = service._reward({"type": "frame", "key": "7", "text": "Золотая рамка"}, 1)
    assert reward == {"type": "frame", "amount": 1, "text": "Золотая рамка", "key": "7"}
    for bad in ({"type": "frame", "key": "nope", "text": "x"}, {"type": "frame", "key": "gold", "text": "x"}):
        try:
            service._reward(bad, 1)
            raise AssertionError("must refuse")
        except service.PassError:
            pass
    cosmetics.grant(db, user, reward, active_season)
    db.commit()
    assert cosmetics.frame_keys(db, [user.id]) == {user.id: "7"}
    h = auth(user)
    me = client.get("/users/me/profile", headers=h).json()
    assert me["frame"] == "7"
    col = client.get("/season-pass/cosmetics", headers=h).json()
    assert [f["key"] for f in col["frames"]] == ["7"]
    # An older app that does not send frame_id leaves the frame alone.
    assert client.put("/season-pass/cosmetics/equip", json={"badge_id": None, "title_id": None}, headers=h).status_code == 200
    assert client.get("/users/me/profile", headers=h).json()["frame"] == "7"
    # Sending frame_id null takes it off.
    client.put("/season-pass/cosmetics/equip", json={"frame_id": None}, headers=h)
    assert client.get("/users/me/profile", headers=h).json()["frame"] is None


def test_catalog_upload_art_and_title_key(client, db, make_user, auth, admin_headers, active_season):
    png = b"\x89PNG\r\n\x1a\n" + b"0" * 32
    r = client.post("/admin/cosmetics", headers=admin_headers, data={"kind": "title", "name": "Хранитель"}, files={"image": ("t.png", png, "image/png")})
    assert r.status_code == 201
    item = r.json()
    assert client.get(f"/cosmetics/art/{item['id']}").status_code == 200  # public artwork
    assert client.post("/admin/cosmetics", headers=admin_headers, data={"kind": "title", "name": "x"}, files={"image": ("t.jpg", png, "image/jpeg")}).status_code == 422
    user = make_user()
    reward = service._reward({"type": "title", "key": str(item["id"]), "text": ""}, 1)
    cosmetics.grant(db, user, reward, active_season)
    db.commit()
    me = client.get("/users/me/profile", headers=auth(user)).json()
    assert me["title"] == "Хранитель" and me["title_key"] == str(item["id"])
    assert client.delete(f"/admin/cosmetics/{item['id']}", headers=admin_headers).status_code == 409  # already earned
