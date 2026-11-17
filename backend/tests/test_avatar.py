"""Avatar built from parts: the Studio's file is imported (the same ID updates, never duplicates), the phone
downloads the catalog, saving checks the choice, the old photo upload is switched off."""

import base64
import json

PNG = b"\x89PNG\r\n\x1a\n" + b"1" * 40
PNG2 = b"\x89PNG\r\n\x1a\n" + b"2" * 40


def studio_file(hair_png=PNG, hair_x=600):
    b64 = lambda b: base64.b64encode(b).decode()
    place = lambda x, y, w: {"x": x, "y": y, "w": w, "r": 0, "pivot": "center"}
    return {
        "format": "avatar-items/1",
        "canvas": {"w": 1200, "h": 1600},
        "frame": {"x": 600, "y": 560, "size": 760, "shape": "circle"},
        "slots": [{"id": "cloth", "name": "Одежда"}, {"id": "face", "name": "Голова с лицом"}, {"id": "hair", "name": "Волосы"}],
        "backgrounds": [
            {"id": "bg1", "name": "Розовый", "kind": "solid", "c1": "#FFD0E2"},
            {"id": "bg2", "name": "Фото", "kind": "img", "width": 10, "height": 10, "place": {"x": 0, "y": 0, "s": 1}, "png": b64(PNG)},
        ],
        "items": [
            {"id": "h1", "slot": "hair", "gender": "female", "name": "Хвост", "set": {"id": "s1", "name": "Набор 1"}, "ownPlace": True, "width": 100, "height": 80, "place": {"female": place(hair_x, 400, 500)}, "png": b64(hair_png)},
            {"id": "h2", "slot": "hair", "gender": "male", "name": "Короткая", "set": {"id": "s1", "name": "Набор 1"}, "ownPlace": False, "width": 100, "height": 80, "place": {"male": place(600, 420, 480)}, "png": b64(PNG)},
            {"id": "f1", "slot": "face", "gender": "both", "name": "Лицо", "set": {"id": "s1", "name": "Набор 1"}, "ownPlace": False, "width": 100, "height": 100, "place": {"male": place(600, 560, 420), "female": place(600, 540, 400)}, "png": b64(PNG)},
        ],
    }


def upload(client, headers, data):
    return client.post("/admin/avatar/import", headers=headers, files={"file": ("guyo-avatar-items.json", json.dumps(data).encode(), "application/json")})


def test_import_is_idempotent_and_updates_by_id(client, admin_headers):
    r = upload(client, admin_headers, studio_file())
    assert r.status_code == 200, r.text
    rep = r.json()
    assert (rep["added"], rep["updated"], rep["unchanged"], rep["backgrounds_added"]) == (3, 0, 0, 2)
    v1 = rep["version"]
    again = upload(client, admin_headers, studio_file()).json()
    assert (again["added"], again["updated"], again["unchanged"]) == (0, 0, 3, )
    assert again["version"] == v1, "nothing changed, the catalog version stays"
    moved = upload(client, admin_headers, studio_file(hair_png=PNG2, hair_x=640)).json()
    assert (moved["added"], moved["updated"], moved["unchanged"]) == (0, 1, 2)
    assert moved["version"] == v1 + 1
    cat = client.get("/admin/avatar/catalog", headers=admin_headers).json()
    assert len(cat["items"]) == 3, "no duplicates"
    hair = next(i for i in cat["items"] if i["id"] == "h1")
    assert hair["version"] == 2 and hair["place"]["female"]["x"] == 640 and hair["own_place"] is True


def test_import_refuses_wrong_files(client, admin_headers):
    assert client.post("/admin/avatar/import", headers=admin_headers, files={"file": ("x.json", b"not json", "application/json")}).status_code == 422
    assert upload(client, admin_headers, {"format": "other", "items": []}).status_code == 422
    bad = studio_file()
    bad["items"][0]["png"] = base64.b64encode(b"GIF89a....").decode()
    assert upload(client, admin_headers, bad).status_code == 422


def test_catalog_for_the_app_and_since(client, db, make_user, auth, admin_headers):
    upload(client, admin_headers, studio_file())
    user = make_user()
    h = auth(user)
    cat = client.get("/avatar/catalog", headers=h).json()
    assert [i["id"] for i in cat["items"]] == ["f1", "h1", "h2"] or {i["id"] for i in cat["items"]} == {"h1", "h2", "f1"}
    assert cat["frame"]["size"] == 760 and [s["id"] for s in cat["slots"]] == ["cloth", "face", "hair"]
    assert cat["sets"] == [{"id": "s1", "name": "Набор 1"}]
    assert all(i["url"] for i in cat["items"]) and {b["id"] for b in cat["backgrounds"]} == {"bg1", "bg2"}
    assert client.get(f"/avatar/catalog?since={cat['version']}", headers=h).json()["unchanged"] is True
    # an admin switching a part off removes it from the app and moves the version
    assert client.patch("/admin/avatar/items/h2", headers=admin_headers, json={"active": False}).status_code == 200
    cat2 = client.get(f"/avatar/catalog?since={cat['version']}", headers=h).json()
    assert cat2["unchanged"] is False and {i["id"] for i in cat2["items"]} == {"h1", "f1"}
    assert client.get("/avatar/catalog").status_code in (401, 403)


def test_save_avatar_checks_the_choice_and_replaces_the_picture(client, db, make_user, auth, admin_headers):
    upload(client, admin_headers, studio_file())
    user = make_user()
    h = auth(user)
    good = {"gender": "female", "slots": {"hair": "h1", "face": "f1"}, "bg": "bg1"}
    r = client.put("/users/me/avatar-look", headers=h, data={"look": json.dumps(good)}, files={"image": ("a.png", PNG, "image/png")})
    assert r.status_code == 200, r.text
    first = r.json()["avatar_url"]
    me = client.get("/users/me/profile", headers=h).json()
    assert me["avatar_url"] == first and me["avatar_look"]["slots"]["hair"] == "h1"
    # a boy's hair for a girl, an unknown part, a non-PNG picture: refused
    for bad in ({"gender": "female", "slots": {"hair": "h2"}}, {"gender": "female", "slots": {"hair": "nope"}}, {"gender": "alien", "slots": {}}, {"gender": "male", "slots": {"hair": "h1"}}):
        assert client.put("/users/me/avatar-look", headers=h, data={"look": json.dumps(bad)}, files={"image": ("a.png", PNG, "image/png")}).status_code == 422
    assert client.put("/users/me/avatar-look", headers=h, data={"look": json.dumps(good)}, files={"image": ("a.jpg", b"\xff\xd8\xff", "image/jpeg")}).status_code == 422
    # saving again gives a new address: the phone sees it changed and drops its old copy
    second = client.put("/users/me/avatar-look", headers=h, data={"look": json.dumps(good)}, files={"image": ("a.png", PNG2, "image/png")}).json()["avatar_url"]
    assert second != first


def test_photo_upload_is_off(client, make_user, auth):
    user = make_user()
    r = client.post("/users/me/avatar", headers=auth(user), files={"avatar": ("a.png", PNG, "image/png")})
    assert r.status_code == 410
