"""Errors the mobile app catches are reported here, and listed for admins."""

import time
from collections import defaultdict, deque
from datetime import datetime

from fastapi import APIRouter, Depends, Header, Request, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin
from app.core.security import decode_access_token
from app.database import get_db
from app.models.client_error import ClientError

router = APIRouter(tags=["client-errors"])

# At most this many reports per client address per minute -- a crash loop
# must not flood the table.
_PER_MINUTE = 20
_recent: dict[str, deque] = defaultdict(deque)


class ClientErrorIn(BaseModel):
    message: str = Field(min_length=1, max_length=4000)
    stack: str | None = Field(default=None, max_length=12000)
    platform: str | None = Field(default=None, max_length=32)


class ClientErrorOut(BaseModel):
    id: int
    user_id: int | None
    app_build: int | None
    platform: str | None
    message: str
    stack: str | None
    created_at: datetime


@router.post("/client-errors", status_code=status.HTTP_204_NO_CONTENT)
def report_client_error(
    payload: ClientErrorIn,
    request: Request,
    db: Session = Depends(get_db),
    authorization: str | None = Header(default=None),
    x_app_build: int | None = Header(default=None),
):
    """Works logged in or not (a crash can happen before login): the user
    is attached when a valid token comes with it."""
    key = request.client.host if request.client else "?"
    now = time.monotonic()
    window = _recent[key]
    while window and now - window[0] > 60:
        window.popleft()
    if len(window) >= _PER_MINUTE:
        return
    window.append(now)

    user_id = None
    if authorization and authorization.lower().startswith("bearer "):
        try:
            token = decode_access_token(authorization[7:])
            if token.role == "user":
                user_id = token.subject
        except Exception:
            pass
    db.add(
        ClientError(
            user_id=user_id,
            app_build=x_app_build,
            platform=payload.platform,
            message=payload.message,
            stack=payload.stack,
        )
    )
    db.commit()


@router.get("/admin/client-errors", response_model=list[ClientErrorOut])
def list_client_errors(limit: int = 100, db: Session = Depends(get_db), _admin=Depends(get_current_admin)):
    return db.query(ClientError).order_by(ClientError.id.desc()).limit(min(max(limit, 1), 500)).all()
