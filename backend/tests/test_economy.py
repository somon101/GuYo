from datetime import timedelta

from app.achievements.streak import record_activity
from app.core.dates import dushanbe_today
from app.economy.service import buy_product, open_gift, use_streak_merge
from app.models.achievement import UserActivityDay, UserStreakFreeze
from app.models.economy import GiftDefinition, ShopProduct


def test_daily_gift_grants_diamonds_and_shop_debits_wallet(db, make_user):
    user = make_user()
    record_activity(db, user)
    gift = db.query(GiftDefinition).filter_by(key="daily-chest").one()
    gift.enabled = True  # off by default: diamonds come from the pass
    opened = open_gift(db, user, gift)
    db.commit()
    assert opened.kind == "diamonds"
    assert 5 <= user.diamonds_balance <= 25

    product = db.query(ShopProduct).filter_by(sku="streak-freeze-1").one()
    user.diamonds_balance = 50
    buy_product(db, user, product)
    db.commit()
    assert user.diamonds_balance == 0
    assert user.streak_freezes == 1
    gift.enabled = False
    db.commit()


def test_streak_merge_counts_unique_activity_and_spent_freeze_days(db, make_user):
    today = dushanbe_today()
    user = make_user(streak_merge_items=1)
    for offset in (10, 9, 8, 2, 1, 0):
        db.add(UserActivityDay(user_id=user.id, activity_date=today - timedelta(days=offset)))
    db.add(UserStreakFreeze(user_id=user.id, covered_date=today - timedelta(days=7)))
    db.commit()

    result = use_streak_merge(db, user)
    db.commit()

    assert result["current_streak_days"] == 7
    assert result["items_left"] == 0
    assert user.streak_merge_days == 4


def test_admin_gifts_diamonds_by_login_or_id(client, db, make_user, admin_headers):
    from app.models.notification import Notification

    user = make_user(login="Somon")
    r = client.post("/admin/economy/gift", headers=admin_headers, json={"user": "somon", "amount": 150, "note": "Спасибо!"})
    assert r.status_code == 200, r.text
    assert r.json()["diamonds"] == 150
    r = client.post("/admin/economy/gift", headers=admin_headers, json={"user": str(user.public_id), "amount": 50})
    assert r.json()["diamonds"] == 200
    assert db.query(Notification).filter_by(user_id=user.id, source="admin_gift").count() == 2
    assert client.post("/admin/economy/gift", headers=admin_headers, json={"user": "nobody", "amount": 5}).status_code == 404
