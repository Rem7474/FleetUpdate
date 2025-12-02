from datetime import datetime, timedelta
from typing import Optional
import jwt
from passlib.context import CryptContext
from ..config import settings


pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")


def verify_password(plain: str, hashed_or_plain: str, is_hashed: bool) -> bool:
    if is_hashed:
        return pwd_ctx.verify(plain, hashed_or_plain)
    return plain == hashed_or_plain


def create_access_token(subject: str, expires_delta: Optional[timedelta] = None) -> str:
    expire = datetime.utcnow() + (expires_delta or timedelta(hours=8))
    to_encode = {"sub": subject, "exp": expire}
    return jwt.encode(to_encode, settings.jwt_secret, algorithm="HS256")


def decode_token(token: str) -> dict:
    return jwt.decode(token, settings.jwt_secret, algorithms=["HS256"]) 
