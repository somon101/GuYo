"""Password hashing and JWT helpers."""
from datetime import datetime, timedelta, timezone

import bcrypt
from jose import JWTError, jwt

from app.config import get_settings

settings = get_settings()


def hash_password(plain_password: str) -> str:
    salt = bcrypt.gensalt()
    return bcrypt.hashpw(plain_password.encode("utf-8"), salt).decode("utf-8")


def verify_password(plain_password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(plain_password.encode("utf-8"), password_hash.encode("utf-8"))
    except ValueError:
        return False


def create_access_token(*, subject: int, role: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.jwt_expire_minutes)
    payload = {"sub": str(subject), "role": role, "exp": expire}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


class TokenPayload:
    def __init__(self, subject: int, role: str):
        self.subject = subject
        self.role = role


def decode_access_token(token: str) -> TokenPayload | None:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except JWTError:
        return None
    sub = payload.get("sub")
    role = payload.get("role")
    if sub is None or role is None:
        return None
    try:
        return TokenPayload(subject=int(sub), role=role)
    except ValueError:
        return None
