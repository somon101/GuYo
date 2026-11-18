"""The feed: cards made by events, friends first, reach that grows with reactions, hearts and phrases."""

from app.models.feed import FeedCard
from app.models.friendship import Friendship
from app.social import feed as svc


def _friends(db, a, b):
    db.add(Friendship(user_id=a.id, friend_id=b.id))
    db.add(Friendship(user_id=b.id, friend_id=a.id))
    db.commit()


def _card(db, user, kind="streak", data=None, key=None):
    c = svc.post(db, user, kind, data or {"days": 7}, key or f"{kind}:{user.id}:{len(db.query(FeedCard).all())}")
    db.commit()
    return c


def test_cards_are_made_once_and_the_words_card_is_updated(db, make_user):
    u = make_user()
    svc.post_streak(db, u, 5)  # not a milestone
    svc.post_streak(db, u, 7)
    svc.post_streak(db, u, 7)
    db.commit()
    assert [c.kind for c in db.query(FeedCard).all()] == ["streak"]
    svc.post(db, u, "words", {"count": 3}, "words:x", update=True)
    svc.post(db, u, "words", {"count": 9}, "words:x", update=True)
    db.commit()
    assert db.query(FeedCard).filter(FeedCard.dedupe_key == "words:x").one().data == {"count": 9}


def test_friends_first_strangers_by_reach_and_the_views_only_for_the_author(client, db, make_user, auth):
    me, friend, stranger = make_user(), make_user(), make_user()
    _friends(db, me, friend)
    c_friend = _card(db, friend, key="a")
    c_stranger = _card(db, stranger, key="b")
    cards = client.get("/feed", headers=auth(me)).json()["cards"]
    assert [c["id"] for c in cards] == [c_friend.id, c_stranger.id]  # the friend's card is on top
    assert cards[0]["is_friend"] is True and cards[1]["is_friend"] is False
    assert cards[0]["views"] is None  # not mine: no number
    # The author sees how many people saw the card.
    mine = client.get("/feed", headers=auth(stranger)).json()["cards"]
    own = [c for c in mine if c["is_mine"]][0]
    assert own["views"] == 1  # `me` saw it once, however often the feed is opened
    client.get("/feed", headers=auth(me))
    assert [c for c in client.get("/feed", headers=auth(stranger)).json()["cards"] if c["is_mine"]][0]["views"] == 1


def test_a_card_stops_spreading_when_its_group_is_full_and_grows_when_liked(db, make_user):
    author = make_user()
    c = _card(db, author, key="spread")
    c.reach = 2
    db.commit()
    viewers = [make_user() for _ in range(4)]
    from app.models.feed import FeedLike

    got = []
    for v in viewers:
        got.append(len(svc.feed(db, v)["cards"]))
        db.commit()
    assert got == [1, 1, 0, 0]  # the third and fourth stranger never get it
    # Well received by its group: the reach grows.
    db.add(FeedLike(card_id=c.id, user_id=viewers[0].id))
    db.add(FeedLike(card_id=c.id, user_id=viewers[1].id))
    c.likes = 2
    db.commit()
    svc.feed(db, viewers[0])
    db.commit()
    assert db.get(FeedCard, c.id).reach == 6


def test_heart_phrase_likers_hide_and_friends_only(client, db, make_user, auth):
    me, a, b = make_user(), make_user(), make_user()
    card = _card(db, a, key="x")
    h = auth(me)
    r = client.post(f"/feed/{card.id}/like", headers=h).json()
    assert r["liked"] is True and r["likes"] == 1
    assert client.post(f"/feed/{card.id}/like", headers=h).json()["likes"] == 1  # a heart is not counted twice
    client.post(f"/feed/{card.id}/like", headers=auth(b))
    likers = client.get(f"/feed/{card.id}/likers", headers=h).json()
    assert {p["user_id"]: p["relation"] for p in likers} == {me.id: "self", b.id: "none"}
    assert client.delete(f"/feed/{card.id}/like", headers=h).json()["likes"] == 1

    assert client.post(f"/feed/{card.id}/comment", headers=h, json={"phrase": "Огонь!"}).json()["my_comment"] == "Огонь!"
    assert client.post(f"/feed/{card.id}/comment", headers=h, json={"phrase": "своё слово"}).status_code == 404
    again = client.post(f"/feed/{card.id}/comment", headers=h, json={"phrase": "Молодец!"}).json()
    assert again["comments"] == 1 and again["last_comment"]["phrase"] == "Молодец!"
    assert client.delete(f"/feed/{card.id}/comment", headers=h).json()["comments"] == 0

    # «Показывать меня только друзьям»: strangers no longer see a's cards.
    a.feed_friends_only = True
    db.commit()
    assert client.get("/feed", headers=auth(b)).json()["cards"] == []
    a.feed_friends_only = False
    db.commit()
    assert len(client.get("/feed", headers=h).json()["cards"]) == 1
    assert client.post(f"/feed/{card.id}/hide", headers=h).status_code == 204
    assert client.get("/feed", headers=h).json()["cards"] == []
    assert client.post("/feed/99999/like", headers=h).status_code == 404


def test_suggestions_prefer_friends_of_friends_and_skip_known_people(client, db, make_user, auth):
    me, f1, f2, x, y = (make_user() for _ in range(5))
    _friends(db, me, f1)
    _friends(db, me, f2)
    _friends(db, f1, x)
    _friends(db, f2, x)  # two mutual friends
    _friends(db, f1, y)  # one
    page = client.get("/feed", headers=auth(me)).json()
    sug = page["suggestions"]
    assert [s["user_id"] for s in sug[:2]] == [x.id, y.id]
    assert sug[0]["reason"] == "mutual" and sug[0]["count"] == 2
    assert me.id not in {s["user_id"] for s in sug} and f1.id not in {s["user_id"] for s in sug}
    assert page["phrases"][0] == "Молодец!"
