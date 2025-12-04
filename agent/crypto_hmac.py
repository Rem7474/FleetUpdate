import hmac as _stdlib_hmac
import hashlib


def sign_bytes(payload: bytes, key: str) -> str:
    return _stdlib_hmac.new(key.encode("utf-8"), payload, hashlib.sha256).hexdigest()
