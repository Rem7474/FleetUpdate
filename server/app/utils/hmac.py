import hmac
import hashlib


def sign_bytes(payload: bytes, key: str) -> str:
    return hmac.new(key.encode("utf-8"), payload, hashlib.sha256).hexdigest()


def verify_signature(signature_hex: str, payload: bytes, key: str) -> bool:
    calc = sign_bytes(payload, key)
    return hmac.compare_digest(calc, signature_hex)
