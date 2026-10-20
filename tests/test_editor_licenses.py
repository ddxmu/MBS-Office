import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import secrets
import sqlite3
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
import uuid

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "server"))
from mbs_editor_licenses import AUDIENCE, AUTHORITY, ISSUER, MAX_TTL, EditorLicenseIssuer


def verify(envelope, public_key_base64, device, nonce, now):
    point = base64.b64decode(public_key_base64, validate=True)
    expected_id = "mbs-editor-p256-" + hashlib.sha256(point).hexdigest()[:16]
    if envelope["keyId"] != expected_id:
        raise ValueError("Unknown signing key")
    public = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), point)
    raw = base64.b64decode(envelope["payload"], validate=True)
    public.verify(base64.b64decode(envelope["signature"], validate=True), raw, ec.ECDSA(hashes.SHA256()))
    claims = json.loads(raw)
    if (claims["version"] != 1 or claims["issuer"] != ISSUER or claims["audience"] != AUDIENCE
            or claims["authority"] != AUTHORITY or claims["deviceId"] != device
            or claims["nonce"] != nonce or not claims["issuedAt"] <= now < claims["expiresAt"]
            or claims["expiresAt"] - claims["issuedAt"] > MAX_TTL):
        raise ValueError("Invalid claims")
    return claims


class EditorLicenseTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.issuer = EditorLicenseIssuer(self.temp.name)
        self.user = {"id": 7, "email": "editor@example.invalid"}
        self.device = str(uuid.uuid4())
        self.nonce = secrets.token_urlsafe(32)
        self.now = int(time.time())
        self.session_hash = hashlib.sha256(secrets.token_bytes(32)).hexdigest()

    def tearDown(self):
        self.temp.cleanup()

    def issue(self, **kwargs):
        args = dict(user=self.user, session_hash=self.session_hash,
            session_expires_at=self.now + MAX_TTL + 60, device_id=self.device,
            nonce=self.nonce, now=self.now)
        args.update(kwargs)
        return self.issuer.issue(**args)

    def test_signed_bound_claims_and_private_key_persistence(self):
        result = self.issue()
        claims = verify(result, self.issuer.public_key_base64, self.device, self.nonce, self.now)
        self.assertEqual(claims["userId"], 7)
        self.assertEqual(claims["email"], self.user["email"])
        self.assertEqual(claims["sessionHash"], self.session_hash)
        self.assertEqual(claims["expiresAt"], self.now + MAX_TTL)
        self.assertNotEqual(self.issue()["payload"], result["payload"])
        key_file = Path(self.temp.name) / "mbs-editor-signing.pem"
        self.assertEqual(key_file.stat().st_mode & 0o777, 0o600)
        again = EditorLicenseIssuer(self.temp.name)
        self.assertEqual(again.public_key_base64, self.issuer.public_key_base64)
        self.assertEqual(len(base64.b64decode(again.public_key_base64)), 65)
        key_file.chmod(0o644)
        with self.assertRaises(ValueError):
            EditorLicenseIssuer(self.temp.name)
        key_file.chmod(0o600)
        key_file.rename(Path(self.temp.name) / "actual.pem")
        key_file.symlink_to("actual.pem")
        with self.assertRaises(OSError):
            EditorLicenseIssuer(self.temp.name)

    def test_expiry_device_nonce_and_signature_rejection(self):
        result = self.issue(session_expires_at=self.now + 30)
        public = self.issuer.public_key_base64
        for device, nonce, now in [(str(uuid.uuid4()), self.nonce, self.now),
                (self.device, secrets.token_urlsafe(32), self.now),
                (self.device, self.nonce, self.now + 30), (self.device, self.nonce, self.now - 1)]:
            with self.assertRaises(ValueError):
                verify(result, public, device, nonce, now)
        changed = dict(result)
        claims = json.loads(base64.b64decode(result["payload"]))
        claims["userId"] = 123
        changed["payload"] = base64.b64encode(json.dumps(claims).encode()).decode()
        with self.assertRaises(InvalidSignature):
            verify(changed, public, self.device, self.nonce, self.now)
        other = EditorLicenseIssuer(Path(self.temp.name))
        changed = dict(result, keyId="unknown-key")
        with self.assertRaises(ValueError):
            verify(changed, other.public_key_base64, self.device, self.nonce, self.now)

    def test_invalid_request_and_expired_session(self):
        for values in [{"device_id": "not-uuid"}, {"nonce": "short"},
                {"nonce": "A" * 4097}, {"nonce": ["A"]},
                {"session_hash": "wrong"}, {"session_expires_at": self.now}]:
            with self.assertRaises(ValueError):
                self.issue(**values)


@unittest.skipUnless(os.environ.get("MBS_ADMIN_SOURCE"), "Set MBS_ADMIN_SOURCE to test the deployed handler candidate")
class EditorLicenseHTTPTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.old_data_dir = os.environ.get("DATA_DIR")
        cls.old_admin_user = os.environ.get("ADMIN_USER")
        cls.old_admin_password = os.environ.get("ADMIN_PASSWORD")
        os.environ["DATA_DIR"] = cls.temp.name
        os.environ["ADMIN_USER"] = "test"
        os.environ["ADMIN_PASSWORD"] = secrets.token_urlsafe(24)
        source = Path(os.environ["MBS_ADMIN_SOURCE"])
        sys.path.insert(0, str(source.parent))
        spec = importlib.util.spec_from_file_location("mbs_license_admin_test", source)
        cls.app = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.app)
        cls.app.setup()
        class QuietApp(cls.app.App):
            def log_message(self, *args):
                pass
        cls.server = cls.app.ThreadingHTTPServer(("127.0.0.1", 0), QuietApp)
        cls.base = "http://127.0.0.1:" + str(cls.server.server_port) + "/api/mbs/"
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.temp.cleanup()
        if cls.old_data_dir is None:
            os.environ.pop("DATA_DIR", None)
        else:
            os.environ["DATA_DIR"] = cls.old_data_dir
        for name, value in (("ADMIN_USER", cls.old_admin_user), ("ADMIN_PASSWORD", cls.old_admin_password)):
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value

    @classmethod
    def call(cls, route, fields=None, token=None, origin=None, raw=None):
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        if origin:
            headers["Origin"] = origin
        request = urllib.request.Request(cls.base + route,
            data=raw if raw is not None else json.dumps(fields).encode(), headers=headers)
        try:
            response = urllib.request.urlopen(request, timeout=5)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            return response.status, json.load(response), response.headers

    def test_authenticated_http_issuance_and_revocation(self):
        email = "issuer-" + secrets.token_hex(6) + "@example.invalid"
        code, account, _ = self.call("register", {"email": email, "password": secrets.token_urlsafe(24)})
        self.assertEqual(code, 201)
        token = account["token"]
        fields = {"deviceId": str(uuid.uuid4()), "nonce": secrets.token_urlsafe(32)}
        self.assertEqual(self.call("editor/license", fields)[0], 401)
        self.assertEqual(self.call("editor/license", fields, "invalid")[0], 401)
        self.assertEqual(self.call("editor/license", fields, token, "https://wrong.invalid")[0], 403)
        for bad in [{}, [], dict(fields, deviceId="invalid"), dict(fields, nonce="A" * 44)]:
            self.assertEqual(self.call("editor/license", bad, token)[0], 400)
        self.assertEqual(self.call("editor/license", token=token, raw=b"x" * 4097)[0], 400)
        code, result, headers = self.call("editor/license", fields, token, ISSUER)
        self.assertEqual(code, 200)
        self.assertEqual(headers["Cache-Control"], "no-store")
        signer = EditorLicenseIssuer(self.temp.name)
        claims = verify(result, signer.public_key_base64, fields["deviceId"], fields["nonce"], int(time.time()))
        self.assertEqual(claims["email"], email)
        self.assertNotIn(token, json.dumps(result))
        self.call("logout", {}, token)
        self.assertEqual(self.call("editor/license", fields, token)[0], 401)
        _, login, _ = self.call("login", {"email": email, "password": "incorrect-password"})
        self.assertFalse(login["ok"])

    def test_expired_backing_session(self):
        email = "expiry-" + secrets.token_hex(6) + "@example.invalid"
        _, account, _ = self.call("register", {"email": email, "password": secrets.token_urlsafe(24)})
        token = account["token"]
        with sqlite3.connect(self.app.DB_PATH) as db:
            db.execute("update mbs_sessions set expires_at=? where token_hash=?",
                (time.time() - 1, self.app.mbs_session_hash(token)))
        self.assertEqual(self.call("editor/license", {"deviceId": str(uuid.uuid4()),
            "nonce": secrets.token_urlsafe(32)}, token)[0], 401)


if __name__ == "__main__":
    unittest.main(verbosity=2)
