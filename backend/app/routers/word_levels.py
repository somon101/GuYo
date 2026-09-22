"""User-facing read of the word-level ladder -- the same WordLevel rows
admin_word_levels.py manages, just exposed to any logged-in user so the
client can render a word's level (see WordOut.word_level_id on
/learned-words) with the ladder's own name/order, without needing admin
credentials. Read-only: nothing here can create/edit/delete a level."""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.database import get_db
from app.schemas.word_level import WordLevelOut
from app.word_levels import ordered_enabled_levels

router = APIRouter(prefix="/word-levels", tags=["word-levels"])


@router.get("", response_model=list[WordLevelOut])
def list_word_levels(db: Session = Depends(get_db), _user=Depends(get_current_user)):
    """Enabled levels only, lowest score-range first -- the same ordering
    used to determine a word's level in the first place (see
    app/word_levels/service.py's ordered_enabled_levels), so a client
    coloring a red-to-green gradient by this list's own index is always
    consistent with which level a word is actually shown as."""
    levels = ordered_enabled_levels(db)
    return [
        WordLevelOut(
            id=level.id, name=level.name, min_points=level.min_points, max_points=level.max_points,
            order=level.order, enabled=level.enabled,
        )
        for level in levels
    ]
