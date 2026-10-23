"""Account-bound activation codes for Mbs-owned authorization."""
import hashlib
import re
import secrets
import sqlite3
import time


class ActivationError(ValueError):
    pass


class ActivationCodes:
    def __init__(self, database):
        self.database = str(database)
        with sqlite3.connect(self.database) as db:
            db.executescript('''
                create table if not exists mbs_activation_codes (
                  id integer primary key, code_hash text unique not null,
                  hint text not null, user_id integer not null references mbs_users(id),
                  plan text not null, expires_at integer not null,
                  max_devices integer not null, created_at integer not null,
                  revoked_at integer);
                create table if not exists mbs_activation_devices (
                  code_id integer not null references mbs_activation_codes(id),
                  device_id text not null, redeemed_at integer not null,
                  primary key(code_id,device_id));
            ''')

    def create(self, user_id, days, max_devices=1, plan="standard", now=None):
        if (type(user_id) is not int or user_id<=0 or type(days) is not int or not 1<=days<=365
                or type(max_devices) is not int or not 1<=max_devices<=10 or plan not in ("standard","vip")):
            raise ActivationError("账号、有效天数或设备数量不正确")
        now = int(time.time() if now is None else now)
        raw = secrets.token_hex(16).upper()
        code = "MBS-"+"-".join(raw[i:i+8] for i in range(0,32,8))
        with sqlite3.connect(self.database) as db:
            if not db.execute("select 1 from mbs_users where id=?",(user_id,)).fetchone():
                raise ActivationError("注册账号不存在")
            row = db.execute('''insert into mbs_activation_codes
                (code_hash,hint,user_id,plan,expires_at,max_devices,created_at)
                values (?,?,?,?,?,?,?)''',
                (hashlib.sha256(code.encode()).hexdigest(),code[-8:],user_id,plan,now+days*86400,max_devices,now))
            return {"id":row.lastrowid,"code":code,"expiresAt":now+days*86400}

    def revoke(self, code_id, now=None):
        if type(code_id) is not int or code_id<=0:
            raise ActivationError("授权记录不正确")
        with sqlite3.connect(self.database) as db:
            row = db.execute("update mbs_activation_codes set revoked_at=? where id=? and revoked_at is null",
                             (int(time.time() if now is None else now),code_id))
            if not row.rowcount:
                raise ActivationError("授权不存在或已撤销")

    def list_admin(self):
        with sqlite3.connect(self.database) as db:
            db.row_factory = sqlite3.Row
            return [dict(row) for row in db.execute('''select c.id,c.hint,c.plan,c.expires_at,
                c.max_devices,c.created_at,c.revoked_at,u.email,
                (select count(*) from mbs_activation_devices d where d.code_id=c.id) device_count
                from mbs_activation_codes c join mbs_users u on u.id=c.user_id order by c.id desc limit 200''')]

    @staticmethod
    def _public(row, device):
        return {"id":row["id"],"plan":row["plan"],"expiresAt":row["expires_at"],
                "maxDevices":row["max_devices"],"deviceId":device}

    def for_device(self, user_id, device, now=None):
        now = int(time.time() if now is None else now)
        with sqlite3.connect(self.database) as db:
            db.row_factory = sqlite3.Row
            row = db.execute('''select c.* from mbs_activation_codes c join mbs_activation_devices d on d.code_id=c.id
                where c.user_id=? and d.device_id=? and c.revoked_at is null and c.expires_at>?
                order by (c.plan='vip') desc,c.expires_at desc limit 1''',(user_id,device,now)).fetchone()
            return self._public(row,device) if row else None

    def redeem(self, code, user, device, nonce, session_hash, session_expires, issuer, now=None):
        code = code.strip().upper() if isinstance(code,str) else ""
        if not re.fullmatch(r"MBS-(?:[0-9A-F]{8}-){3}[0-9A-F]{8}",code):
            raise ActivationError("授权码格式不正确")
        now = int(time.time() if now is None else now)
        with sqlite3.connect(self.database) as db:
            db.row_factory = sqlite3.Row
            db.execute("begin immediate")
            row = db.execute("select * from mbs_activation_codes where code_hash=?",
                             (hashlib.sha256(code.encode()).hexdigest(),)).fetchone()
            if not row or row["user_id"]!=user["id"] or row["revoked_at"] is not None or row["expires_at"]<=now:
                raise ActivationError("授权码无效、已过期或不属于当前账号")
            bound = db.execute("select 1 from mbs_activation_devices where code_id=? and device_id=?",(row["id"],device)).fetchone()
            count = db.execute("select count(*) from mbs_activation_devices where code_id=?",(row["id"],)).fetchone()[0]
            if not bound and count>=row["max_devices"]:
                raise ActivationError("授权码已达到设备数量上限")
            activation = self._public(row,device)
            grant = issuer.issue(user,session_hash,min(session_expires,row["expires_at"]),device,nonce,now=now,activation=activation)
            db.execute("insert or ignore into mbs_activation_devices (code_id,device_id,redeemed_at) values (?,?,?)",
                       (row["id"],device,now))
            return grant

    def auto_activate(self, user, device, nonce, session_hash, session_expires, issuer, now=None):
        now = int(time.time() if now is None else now)
        with sqlite3.connect(self.database) as db:
            db.row_factory = sqlite3.Row
            db.execute("begin immediate")
            if not db.execute("select 1 from mbs_users where id=?",(user["id"],)).fetchone():
                raise ActivationError("注册账号不存在")
            rows = db.execute('''select c.*,
                exists(select 1 from mbs_activation_devices d where d.code_id=c.id and d.device_id=?) bound,
                (select count(*) from mbs_activation_devices d where d.code_id=c.id) device_count
                from mbs_activation_codes c where c.user_id=?
                order by (c.plan='vip') desc,c.expires_at desc''',(device,user["id"])).fetchall()
            # A first activation grants one year once per account, never again
            # after expiry/revocation or after changing installations.
            if not rows:
                raw = secrets.token_hex(16).upper()
                code = "MBS-"+"-".join(raw[i:i+8] for i in range(0,32,8))
                row = db.execute('''insert into mbs_activation_codes
                    (code_hash,hint,user_id,plan,expires_at,max_devices,created_at)
                    values (?,?,?,'standard',?,1,?)''',
                    (hashlib.sha256(code.encode()).hexdigest(),code[-8:],user["id"],now+365*86400,now))
                rows = [dict(db.execute("select * from mbs_activation_codes where id=?",(row.lastrowid,)).fetchone(),bound=False,device_count=0)]
            valid = [row for row in rows if row["revoked_at"] is None and row["expires_at"]>now]
            row = next((row for row in valid if row["bound"] or row["device_count"]<row["max_devices"]),None)
            activation = self._public(row,device) if row else None
            state = "active" if row else ("device_limit" if valid else
                ("expired" if any(r["revoked_at"] is None for r in rows) else "revoked"))
            grant = issuer.issue(user,session_hash,min(session_expires,row["expires_at"]) if row else session_expires,
                device,nonce,now=now,activation=activation,activation_state=state)
            if row:
                db.execute("insert or ignore into mbs_activation_devices (code_id,device_id,redeemed_at) values (?,?,?)",
                    (row["id"],device,now))
            return grant
