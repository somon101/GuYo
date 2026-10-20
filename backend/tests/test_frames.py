from app.seasonpass import cosmetics, service


def test_frame_reward_is_validated_granted_and_worn(client, db, make_user, auth, active_season):
    user = make_user()
    reward = service._reward({"type": "frame", "key": "gold", "text": "Золотая рамка"}, 1)
    assert reward == {"type": "frame", "amount": 1, "text": "Золотая рамка", "key": "gold"}
    for bad in ({"type": "frame", "key": "nope", "text": "x"}, {"type": "frame", "key": "gold", "text": ""}):
        try:
            service._reward(bad, 1)
            raise AssertionError("must refuse")
        except service.PassError:
            pass
    cosmetics.grant(db, user, reward, active_season)
    db.commit()
    assert cosmetics.frame_keys(db, [user.id]) == {user.id: "gold"}
    h = auth(user)
    me = client.get("/users/me/profile", headers=h).json()
    assert me["frame"] == "gold"
    col = client.get("/season-pass/cosmetics", headers=h).json()
    assert [f["key"] for f in col["frames"]] == ["gold"]
    # An older app that does not send frame_id leaves the frame alone.
    assert client.put("/season-pass/cosmetics/equip", json={"badge_id": None, "title_id": None}, headers=h).status_code == 200
    assert client.get("/users/me/profile", headers=h).json()["frame"] == "gold"
    # Sending frame_id null takes it off.
    client.put("/season-pass/cosmetics/equip", json={"frame_id": None}, headers=h)
    assert client.get("/users/me/profile", headers=h).json()["frame"] is None
