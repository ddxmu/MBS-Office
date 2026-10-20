"""Signed authorization for the Mbs custom editor integration, not vendor licenses."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import stat
import tempfile
import time
import uuid

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec


ISSUER = "https://ttys.ddxmu.com"
AUDIENCE = "mbs.office.editor.custom"
AUTHORITY = "mbs-custom"
MAX_TTL = 30 * 24 * 60 * 60


def validate_request(device_id, nonce):
    if not isinstance(device_id, str) or len(device_id) != 36:
        raise ValueError("Invalid deviceId")
    try:
        if str(uuid.UUID(device_id)) != device_id.lower():
            raise ValueError("Invalid deviceId")
    except (ValueError, AttributeError):
        raise ValueError("Invalid deviceId")
    if not isinstance(nonce, str) or not re.fullmatch(r"[A-Za-z0-9_-]{43}", nonce):
        raise ValueError("Invalid nonce")


class EditorLicenseIssuer:
    def __init__(self, data_dir):
        path = Path(data_dir) / "mbs-editor-signing.pem"
        try:
            fd = os.open(str(path), os.O_RDONLY | os.O_NOFOLLOW)
        except FileNotFoundError:
            key = ec.generate_private_key(ec.SECP256R1(), default_backend())
            pem = key.private_bytes(serialization.Encoding.PEM,
                serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
            fd, temporary = tempfile.mkstemp(prefix=".mbs-editor-signing-", dir=str(path.parent))
            try:
                os.fchmod(fd, 0o600)
                with os.fdopen(fd, "wb") as stream:
                    stream.write(pem)
                    stream.flush()
                    os.fsync(stream.fileno())
                try:
                    os.link(temporary, str(path))
                except FileExistsError:
                    pass  # Another issuer generated the persistent key first.
            finally:
                os.unlink(temporary)
            fd = os.open(str(path), os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd, "rb") as stream:
            metadata = os.fstat(stream.fileno())
            if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid()
                    or stat.S_IMODE(metadata.st_mode) != 0o600):
                raise ValueError("Signing key must be an owner-only regular file")
            pem = stream.read(16385)
            if len(pem) > 16384:
                raise ValueError("Invalid signing key")
        self.key = serialization.load_pem_private_key(pem, password=None, backend=default_backend())
        if not isinstance(self.key, ec.EllipticCurvePrivateKey) or not isinstance(self.key.curve, ec.SECP256R1):
            raise ValueError("Signing key must use P-256")
        public = self.key.public_key().public_bytes(serialization.Encoding.X962,
            serialization.PublicFormat.UncompressedPoint)
        self.public_key_base64 = base64.b64encode(public).decode("ascii")
        self.key_id = "mbs-editor-p256-" + hashlib.sha256(public).hexdigest()[:16]

    def issue(self, user, session_hash, session_expires_at, device_id, nonce, now=None, activation=None):
        validate_request(device_id, nonce)
        now = int(time.time() if now is None else now)
        expires = min(now + MAX_TTL, int(session_expires_at))
        if expires <= now:
            raise ValueError("Session expired")
        if not re.fullmatch(r"[0-9a-f]{64}", session_hash):
            raise ValueError("Invalid session hash")
        claims = {"version": 1, "issuer": ISSUER, "audience": AUDIENCE,
            "authority": AUTHORITY, "userId": int(user["id"]), "email": user["email"],
            "deviceId": device_id, "nonce": nonce, "issuedAt": now, "expiresAt": expires,
            "jti": secrets.token_urlsafe(24), "sessionHash": session_hash}
        if activation is not None:
            claims["activation"] = activation
        payload = json.dumps(claims, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        signature = self.key.sign(payload, ec.ECDSA(hashes.SHA256()))
        return {"payload": base64.b64encode(payload).decode("ascii"),
            "signature": base64.b64encode(signature).decode("ascii"), "keyId": self.key_id}
