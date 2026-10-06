"""Admin Web's view of the memory model while it runs in the shadow: how
much of the history is modelled, and how well it predicts real answers
compared with today's Priority (app/memory/evaluation.py)."""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin
from app.database import get_db
from app.memory.evaluation import evaluate
from app.memory.service import memory_coverage

router = APIRouter(prefix="/admin/memory", tags=["admin-memory"])


@router.get("/evaluation")
def get_memory_evaluation(db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    modelled, total = memory_coverage(db)
    return {"modelled_pairs": modelled, "pairs_with_answers": total, **evaluate(db)}
