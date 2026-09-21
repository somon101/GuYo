"""The ONE reusable mechanism that decides "has this user now earned any
new achievements" -- called after any event that could move a
condition_type's measured value (today: a word crossing the learned
threshold, since that's what changes phrases_opened_count). There is
deliberately no per-achievement if-branch here: every achievement of the
given condition_type is checked the same way, so adding a 5th, 50th, or
500th achievement in Admin Web needs zero code changes.
"""

from sqlalchemy.orm import Session

from app.achievements.conditions import CONDITION_TYPES
from app.models.achievement import Achievement, UserAchievement
from app.models.user import User


def check_and_grant_achievements(db: Session, user: User, condition_type: str) -> list[Achievement]:
    """Computes the user's current value for `condition_type` once, then
    grants every enabled, not-yet-earned Achievement of that type whose
    condition_value is now met. Returns the newly granted ones (empty list
    if none) -- callers can use this to show a "you just earned X"
    celebration, but nothing here depends on that; the grant itself is
    already durable (flushed) regardless of whether anyone reads the
    return value.

    Safe to call defensively/often: an achievement already in
    UserAchievement is never reconsidered, so calling this twice for the
    same event grants nothing the second time."""
    compute_value = CONDITION_TYPES.get(condition_type)
    if compute_value is None:
        return []
    current_value = compute_value(db, user)

    already_earned_ids = {
        row[0]
        for row in db.query(UserAchievement.achievement_id).filter(UserAchievement.user_id == user.id).all()
    }

    query = db.query(Achievement).filter(
        Achievement.condition_type == condition_type,
        Achievement.enabled.is_(True),
        Achievement.condition_value <= current_value,
    )
    if already_earned_ids:
        query = query.filter(~Achievement.id.in_(already_earned_ids))
    candidates = query.all()

    newly_granted = []
    for achievement in candidates:
        db.add(UserAchievement(user_id=user.id, achievement_id=achievement.id))
        newly_granted.append(achievement)
    if newly_granted:
        db.flush()
    return newly_granted
