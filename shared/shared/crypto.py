import hmac
import hashlib


def hmac_sign_bytes(payload: bytes, key: str) -> str:
    return hmac.new(key.encode("utf-8"), payload, hashlib.sha256).hexdigest()
