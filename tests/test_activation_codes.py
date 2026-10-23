import base64
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import secrets
import sqlite3
import sys
import tempfile
import time
import unittest
import uuid

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"server"))
from mbs_activation_codes import ActivationCodes, ActivationError
from mbs_editor_licenses import EditorLicenseIssuer


class ActivationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.database = Path(self.temp.name)/"test.db"
        with sqlite3.connect(self.database) as db:
            db.executescript("create table mbs_users (id integer primary key,email text);insert into mbs_users values(1,'one@example.invalid'),(2,'two@example.invalid');")
        self.store = ActivationCodes(self.database)
        self.issuer = EditorLicenseIssuer(self.temp.name)
        self.user = {"id":1,"email":"one@example.invalid"}
        self.now = int(time.time())
        self.device = str(uuid.uuid4())

    def tearDown(self):
        self.temp.cleanup()

    def redeem(self, code, **values):
        args = dict(code=code,user=self.user,device=self.device,nonce=secrets.token_urlsafe(32),
            session_hash=hashlib.sha256(b"session").hexdigest(),session_expires=self.now+86400,
            issuer=self.issuer,now=self.now)
        args.update(values)
        return self.store.redeem(**args)

    def auto(self, **values):
        args = dict(user=self.user,device=self.device,nonce=secrets.token_urlsafe(32),
            session_hash=hashlib.sha256(b"session").hexdigest(),session_expires=self.now+400*86400,
            issuer=self.issuer,now=self.now)
        args.update(values)
        return json.loads(base64.b64decode(self.store.auto_activate(**args)["payload"]))

    def test_first_auto_activation_gets_one_year_only_once(self):
        first = self.auto()
        self.assertEqual(first["activationState"],"active")
        self.assertEqual(first["activation"]["plan"],"standard")
        self.assertEqual(first["activation"]["expiresAt"],self.now+365*86400)
        self.assertEqual(self.auto()["activation"]["id"],first["activation"]["id"])
        expired = self.auto(now=self.now+366*86400)
        self.assertEqual(expired["activationState"],"expired")
        self.assertNotIn("activation",expired)
        self.assertEqual(len(self.store.list_admin()),1)

    def test_auto_activation_honors_device_limit_and_manual_renewal(self):
        issued = self.store.create(1,1,max_devices=2,plan="vip",now=self.now)
        self.assertEqual(self.auto()["activation"]["id"],issued["id"])
        self.assertEqual(self.auto(device=str(uuid.uuid4()))["activationState"],"active")
        self.assertEqual(self.auto(device=str(uuid.uuid4()))["activationState"],"device_limit")
        self.store.revoke(issued["id"],now=self.now)
        self.assertEqual(self.auto()["activationState"],"revoked")
        renewed = self.store.create(1,365,plan="vip",now=self.now)
        self.assertEqual(self.auto()["activation"]["id"],renewed["id"])
        self.assertEqual(self.store.list_admin()[0]["device_count"],1)

    def test_auto_activation_transaction_rejects_bad_nonce_and_device_race(self):
        with self.assertRaises(ValueError): self.auto(nonce="bad")
        self.assertEqual(self.store.list_admin(),[])
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda device:self.auto(device=device)["activationState"],
                [str(uuid.uuid4()),str(uuid.uuid4())]))
        self.assertCountEqual(results,["active","device_limit"])
        self.assertEqual(len(self.store.list_admin()),1)
        self.assertEqual(self.store.list_admin()[0]["device_count"],1)

    def test_code_is_hashed_and_claims_are_bound(self):
        issued = self.store.create(1,30,plan="vip",now=self.now)
        claims = json.loads(base64.b64decode(self.redeem(issued["code"])["payload"]))
        self.assertEqual(claims["activation"]["plan"],"vip")
        self.assertEqual(claims["activation"]["deviceId"],self.device)
        self.assertEqual(claims["expiresAt"],self.now+86400)
        self.assertNotIn(issued["code"].encode(),self.database.read_bytes())
        self.assertNotIn("code_hash",self.store.list_admin()[0])
        self.redeem(issued["code"].lower())
        self.assertEqual(self.store.list_admin()[0]["device_count"],1)

    def test_wrong_account_revocation_expiry_and_device_limit(self):
        issued = self.store.create(1,1,now=self.now)
        with self.assertRaises(ActivationError): self.redeem(issued["code"],user={"id":2,"email":"two@example.invalid"})
        self.redeem(issued["code"])
        with self.assertRaises(ActivationError): self.redeem(issued["code"],device=str(uuid.uuid4()))
        self.assertIsNotNone(self.store.for_device(1,self.device,now=self.now))
        self.assertIsNone(self.store.for_device(1,self.device,now=self.now+86400))
        with self.assertRaises(ActivationError): self.redeem(issued["code"],now=self.now+86400)
        self.store.revoke(issued["id"],now=self.now)
        self.assertIsNone(self.store.for_device(1,self.device,now=self.now))
        with self.assertRaises(ActivationError): self.redeem(issued["code"])

    def test_year_activation_keeps_full_expiry_in_short_lived_grant(self):
        issued = self.store.create(1,365,plan="vip",now=self.now)
        claims = json.loads(base64.b64decode(self.redeem(issued["code"])["payload"]))
        self.assertEqual(claims["expiresAt"],self.now+86400)
        self.assertEqual(claims["activation"]["expiresAt"],self.now+365*86400)
        self.assertIsNotNone(self.store.for_device(1,self.device,now=self.now+364*86400))
        self.assertIsNone(self.store.for_device(1,self.device,now=self.now+365*86400))

    def test_concurrent_redemption_cannot_exceed_device_limit(self):
        code = self.store.create(1,1)["code"]
        def attempt(device):
            try: self.redeem(code,device=device); return True
            except ActivationError: return False
        with ThreadPoolExecutor(max_workers=2) as pool:
            self.assertEqual(sum(pool.map(attempt,[str(uuid.uuid4()),str(uuid.uuid4())])),1)
        self.assertEqual(self.store.list_admin()[0]["device_count"],1)

    def test_invalid_requests_do_not_consume_a_device(self):
        code = self.store.create(1,1)["code"]
        with self.assertRaises(ValueError): self.redeem(code,nonce="bad")
        self.assertEqual(self.store.list_admin()[0]["device_count"],0)
        for values in [(0,30,1,"standard"),(1,0,1,"standard"),(1,30,11,"standard"),(1,30,1,"unknown")]:
            with self.assertRaises(ActivationError): self.store.create(*values)


if __name__ == "__main__": unittest.main()
