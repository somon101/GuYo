"""Friend requests and requests to join a closed team."""

from datetime import timedelta

from app.core.dates import utc_now
from app.models.friendship import Friendship
from app.models.social import TeamJoinRequest
from app.seasonpass import teams as team_svc


def test_friend_request_asked_taken_back_and_accepted(client, db, make_user, auth):
    a, b = make_user(), make_user()
    ha, hb = auth(a), auth(b)

    r = client.post("/friends/requests", headers=ha, json={"user_id": b.id})
    assert r.status_code == 200 and r.json()["relation"] == "sent"
    # Asking twice changes nothing.
    assert client.post("/friends/requests", headers=ha, json={"user_id": b.id}).json()["relation"] == "sent"
    assert [p["user_id"] for p in client.get("/friends/requests", headers=hb).json()["incoming"]] == [a.id]
    assert [p["user_id"] for p in client.get("/friends/requests", headers=ha).json()["outgoing"]] == [b.id]

    # Taken back: nothing is waiting any more.
    assert client.delete(f"/friends/requests/{b.id}", headers=ha).json()["relation"] == "none"
    assert client.get("/friends/requests", headers=hb).json()["incoming"] == []

    client.post("/friends/requests", headers=ha, json={"user_id": b.id})
    r = client.post(f"/friends/requests/{a.id}/accept", headers=hb)
    assert r.json()["relation"] == "friend"
    assert db.query(Friendship).filter(Friendship.user_id.in_([a.id, b.id])).count() == 2
    assert client.get("/friends/requests", headers=hb).json() == {"incoming": [], "outgoing": []}
    assert client.post("/friends/requests", headers=ha, json={"user_id": b.id}).status_code == 409  # already friends


def test_friend_request_declined_and_crossed(client, db, make_user, auth):
    a, b, c = make_user(), make_user(), make_user()
    ha, hb, hc = auth(a), auth(b), auth(c)
    client.post("/friends/requests", headers=ha, json={"user_id": b.id})
    assert client.post(f"/friends/requests/{a.id}/decline", headers=hb).json()["relation"] == "none"
    assert db.query(Friendship).count() == 0
    assert client.post(f"/friends/requests/{a.id}/accept", headers=hb).status_code == 409  # nothing to accept
    # Both ask each other: they are friends at once.
    client.post("/friends/requests", headers=hc, json={"user_id": a.id})
    assert client.post("/friends/requests", headers=ha, json={"user_id": c.id}).json()["relation"] == "friend"
    assert client.post("/friends/requests", headers=ha, json={"user_id": a.id}).status_code == 409  # not oneself


def test_closed_team_takes_a_request_only_the_creator_answers(client, db, make_user, auth, active_season):
    owner, asker, other = make_user(), make_user(), make_user()
    ho, ha, hx = auth(owner), auth(asker), auth(other)
    team = client.post("/teams", headers=ho, json={"name": "Closed ones", "is_open": False}).json()["team"]
    tid = team["id"]

    assert client.post(f"/teams/{tid}/join", headers=ha).status_code == 409  # closed: no instant joining
    listed = {t["id"]: t for t in client.get("/teams/open?closed=true", headers=ha).json()}
    assert listed[tid]["is_open"] is False and listed[tid]["requested"] is False
    assert tid not in {t["id"] for t in client.get("/teams/open", headers=ha).json()}

    state = client.post(f"/teams/{tid}/request", headers=ha).json()
    assert state["my_requests"] == [tid]
    assert {t["id"]: t for t in client.get("/teams/open?closed=true", headers=ha).json()}[tid]["requested"] is True
    owner_state = client.get("/teams/me", headers=ho).json()
    assert [r["user_id"] for r in owner_state["requests"]] == [asker.id]
    assert client.get("/teams/me", headers=ha).json()["requests"] == []  # only the creator sees them

    # Somebody else cannot answer; the creator can.
    assert client.post("/teams/me/requests/%d/accept" % asker.id, headers=hx).status_code == 409
    state = client.post(f"/teams/me/requests/{asker.id}/accept", headers=ho).json()
    assert asker.id in [m["user_id"] for m in state["team"]["members"]]
    assert client.get("/teams/me", headers=ha).json()["team"]["id"] == tid
    assert db.query(TeamJoinRequest).filter(TeamJoinRequest.user_id == asker.id).count() == 0


def test_declined_request_cannot_be_repeated_for_a_day_and_open_teams_need_none(client, db, make_user, auth, active_season):
    owner, asker = make_user(), make_user()
    ho, ha = auth(owner), auth(asker)
    tid = client.post("/teams", headers=ho, json={"name": "Quiet", "is_open": False}).json()["team"]["id"]
    client.post(f"/teams/{tid}/request", headers=ha)
    client.post(f"/teams/me/requests/{asker.id}/decline", headers=ho)
    assert client.post(f"/teams/{tid}/request", headers=ha).status_code == 409
    item = db.query(TeamJoinRequest).one()
    item.declined_at = utc_now() - timedelta(days=2)
    db.commit()
    assert client.post(f"/teams/{tid}/request", headers=ha).json()["my_requests"] == [tid]  # asks again

    open_id = client.post("/teams", headers=auth(make_user()), json={"name": "Wide open", "is_open": True}).json()["team"]["id"]
    assert client.post(f"/teams/{open_id}/request", headers=ha).status_code == 409
    # A request taken back leaves nothing waiting.
    client.delete(f"/teams/{tid}/request", headers=ha)
    assert client.get("/teams/me", headers=ho).json()["requests"] == []
