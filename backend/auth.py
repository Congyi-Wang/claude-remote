import os
from datetime import datetime, timedelta, timezone
from jose import jwt, JWTError

PIN = os.getenv("PIN", "000427")
JWT_SECRET = os.getenv("JWT_SECRET", "claude-remote-jwt-secret-key-2026")
JWT_ALGORITHM = "HS256"
JWT_EXPIRE_DAYS = 30


def verify_pin(pin: str) -> bool:
    return pin == PIN


def create_token() -> str:
    expire = datetime.now(timezone.utc) + timedelta(days=JWT_EXPIRE_DAYS)
    return jwt.encode({"exp": expire, "sub": "claude-remote"}, JWT_SECRET, algorithm=JWT_ALGORITHM)


def verify_token(token: str) -> bool:
    try:
        jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        return True
    except JWTError:
        return False
