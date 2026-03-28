import base64
import hashlib
import hmac
import json
import os
import time
from dataclasses import dataclass
from typing import Any, Callable

from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

AUTH_SECRET = os.getenv("AUTH_SECRET", "scbbank-dev-auth-secret")
ACCESS_TOKEN_TTL_SECONDS = int(os.getenv("ACCESS_TOKEN_TTL_SECONDS", "43200"))
INTERNAL_SERVICE_TOKEN = os.getenv("INTERNAL_SERVICE_TOKEN", "scbbank-internal-token")

ADMIN_USERNAME = os.getenv("ADMIN_USERNAME", "admin")
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "admin123")

_ALLOWED_ROLES = {"admin", "user"}
_http_bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class AuthContext:
    subject: str
    role: str
    account_id: int | None


class AuthError(Exception):
    pass


def _base64url_encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("utf-8").rstrip("=")


def _base64url_decode(raw: str) -> bytes:
    padding = "=" * (-len(raw) % 4)
    return base64.urlsafe_b64decode(raw + padding)


def _sign(payload_segment: str) -> str:
    digest = hmac.new(
        AUTH_SECRET.encode("utf-8"),
        payload_segment.encode("utf-8"),
        hashlib.sha256,
    ).digest()
    return _base64url_encode(digest)


def issue_access_token(
    subject: str,
    role: str,
    account_id: int | None = None,
    ttl_seconds: int | None = None,
) -> str:
    if role not in _ALLOWED_ROLES:
        raise ValueError(f"Unsupported role: {role}")

    now = int(time.time())
    expiry = now + (ttl_seconds if ttl_seconds is not None else ACCESS_TOKEN_TTL_SECONDS)

    payload = {
        "sub": subject,
        "role": role,
        "account_id": account_id,
        "iat": now,
        "exp": expiry,
    }

    payload_segment = _base64url_encode(
        json.dumps(payload, separators=(",", ":")).encode("utf-8")
    )
    signature = _sign(payload_segment)
    return f"{payload_segment}.{signature}"


def decode_access_token(token: str) -> dict[str, Any]:
    try:
        payload_segment, signature = token.split(".", maxsplit=1)
    except ValueError as exc:
        raise AuthError("Malformed token") from exc

    expected_signature = _sign(payload_segment)
    if not hmac.compare_digest(signature, expected_signature):
        raise AuthError("Invalid token signature")

    try:
        payload = json.loads(_base64url_decode(payload_segment).decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError, ValueError) as exc:
        raise AuthError("Invalid token payload") from exc

    role = payload.get("role")
    if role not in _ALLOWED_ROLES:
        raise AuthError("Invalid token role")

    expiry = payload.get("exp")
    if not isinstance(expiry, int) or expiry <= int(time.time()):
        raise AuthError("Token expired")

    subject = payload.get("sub")
    if not isinstance(subject, str) or not subject:
        raise AuthError("Invalid token subject")

    account_id = payload.get("account_id")
    if account_id is not None and not isinstance(account_id, int):
        raise AuthError("Invalid account_id claim")

    return payload


def _token_to_context(token: str) -> AuthContext:
    payload = decode_access_token(token)
    return AuthContext(
        subject=payload["sub"],
        role=payload["role"],
        account_id=payload.get("account_id"),
    )


def _context_from_credentials(
    credentials: HTTPAuthorizationCredentials | None,
) -> AuthContext:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization header",
        )

    if credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization scheme must be Bearer",
        )

    try:
        return _token_to_context(credentials.credentials)
    except AuthError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
        ) from exc


def is_internal_service_token(token: str | None) -> bool:
    return bool(token) and hmac.compare_digest(token, INTERNAL_SERVICE_TOKEN)


def get_auth_context(
    credentials: HTTPAuthorizationCredentials | None = Depends(_http_bearer),
) -> AuthContext:
    return _context_from_credentials(credentials)


def get_auth_or_internal_context(
    credentials: HTTPAuthorizationCredentials | None = Depends(_http_bearer),
    internal_token: str | None = Header(default=None, alias="X-Internal-Token"),
) -> AuthContext:
    if is_internal_service_token(internal_token):
        return AuthContext(subject="internal-service", role="admin", account_id=None)
    return _context_from_credentials(credentials)


def require_internal_service(
    internal_token: str | None = Header(default=None, alias="X-Internal-Token"),
) -> None:
    if not is_internal_service_token(internal_token):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid internal service token",
        )


def require_roles(*roles: str) -> Callable[[AuthContext], AuthContext]:
    allowed_roles = set(roles)

    def dependency(auth: AuthContext = Depends(get_auth_context)) -> AuthContext:
        if auth.role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient permissions",
            )
        return auth

    return dependency


def require_admin_or_internal(
    credentials: HTTPAuthorizationCredentials | None = Depends(_http_bearer),
    internal_token: str | None = Header(default=None, alias="X-Internal-Token"),
) -> AuthContext:
    if is_internal_service_token(internal_token):
        return AuthContext(subject="internal-service", role="admin", account_id=None)

    auth = _context_from_credentials(credentials)
    if auth.role != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin permissions required",
        )
    return auth


def ensure_account_access(auth: AuthContext, account_id: int) -> None:
    if auth.role == "admin":
        return

    if auth.account_id != account_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account access denied",
        )
