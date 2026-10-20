"""HTTP routes added to the existing Mbs account/admin service."""
import datetime
import hashlib
import hmac
import html
import sqlite3
import time
from urllib.parse import parse_qs

from mbs_activation_codes import ActivationCodes, ActivationError
from mbs_editor_licenses import EditorLicenseIssuer, validate_request


class ActivationRoutes:
    def activation_store(self):
        return ActivationCodes(self.activation_context()["database"])

    def activation_csrf(self):
        context = self.activation_context()
        return hmac.new(context["secret"](),b"mbs-activation:"+self.headers.get("Cookie", "").encode(),hashlib.sha256).hexdigest()

    def activation_admin_page(self, notice="", code="", status=200):
        context = self.activation_context()
        esc = html.escape
        token = self.activation_csrf()
        with sqlite3.connect(context["database"]) as db:
            users = db.execute("select id,email from mbs_users order by email").fetchall()
        options = "".join(f'<option value="{uid}">{esc(email)}</option>' for uid,email in users)
        rows = []
        now = time.time()
        for row in self.activation_store().list_admin():
            state = "已撤销" if row["revoked_at"] else ("已过期" if row["expires_at"]<=now else "有效")
            expiry = datetime.datetime.fromtimestamp(row["expires_at"],datetime.timezone(datetime.timedelta(hours=8))).strftime("%Y-%m-%d %H:%M")
            button = "" if row["revoked_at"] else f'<form method="post" action="/admin/mbs-licenses/revoke"><input type="hidden" name="csrf" value="{token}"><input type="hidden" name="id" value="{row["id"]}"><button class="danger">撤销</button></form>'
            rows.append(f'<tr><td>{row["id"]}</td><td>{esc(row["email"])}</td><td>…{esc(row["hint"])}</td><td>{esc(row["plan"])}</td><td>{expiry}</td><td>{row["device_count"]}/{row["max_devices"]}</td><td>{state}</td><td>{button}</td></tr>')
        message = f'<div class="flash">{esc(notice)}</div>' if notice else ""
        if code:
            message += f'<section class="panel"><b>新授权码（仅显示这一次，请保存）</b><pre style="white-space:pre-wrap;user-select:all">{esc(code)}</pre></section>'
        body = f'''<section class="panel"><h1>Mbs Office 授权码管理</h1>
<p>授权码绑定已注册账号；兑换后绑定客户端设备。撤销或到期后，客户端联网续期时同步状态。基础编辑不因授权码失效而被锁定。</p>{message}
<form method="post" action="/admin/mbs-licenses/create"><input type="hidden" name="csrf" value="{token}">
<label>注册账号<select name="userId" required>{options}</select></label>
<div class="grid"><label>有效天数<input type="number" name="days" min="1" max="365" value="30" required></label>
<label>设备上限<input type="number" name="maxDevices" min="1" max="10" value="1" required></label>
<label>授权等级<select name="plan"><option value="standard">Mbs 标准授权</option><option value="vip">Mbs VIP 授权</option></select></label></div>
<button type="submit">生成授权码</button></form></section>
<section class="panel" style="overflow-x:auto"><h2>授权记录</h2><table><thead><tr><th>ID</th><th>账号</th><th>码尾号</th><th>等级</th><th>到期时间（香港）</th><th>设备</th><th>状态</th><th>操作</th></tr></thead><tbody>{"".join(rows)}</tbody></table></section>'''
        return self.send_html(context["page"]("Mbs 授权码",body),status)

    def activation_get(self, parsed):
        if parsed.path == "/admin/mbs-licenses":
            if not self.is_admin(): self.redirect("/admin/login")
            else: self.activation_admin_page()
            return True
        if parsed.path == "/api/mbs/activation/status":
            context = self.activation_context()
            user = context["user"](context["token"](self.headers))
            if not user:
                self.send_json({"ok":False,"error":"请先登录账号"},401)
            else:
                device = parse_qs(parsed.query).get("deviceId",[""])[0]
                try:
                    validate_request(device,"n"*43)
                    self.send_json({"ok":True,"activation":self.activation_store().for_device(user["id"],device)})
                except ValueError:
                    self.send_json({"ok":False,"error":"设备标识不正确"},400)
            return True
        return False

    def activation_post(self, path):
        admin = path in ("/admin/mbs-licenses/create","/admin/mbs-licenses/revoke")
        if not admin and path != "/api/mbs/activation/redeem":
            return False
        if admin and not self.is_admin():
            self.redirect("/admin/login"); return True
        if self.headers.get("Origin") not in (None,"https://ttys.ddxmu.com"):
            self.send_json({"ok":False,"error":"请求来源不正确"},403); return True
        try:
            length = int(self.headers.get("Content-Length","0"))
            if not 0<length<=4096: raise ValueError("请求大小不正确")
            fields = self.body_fields()
            if not isinstance(fields,dict): raise ValueError("请求格式不正确")
            if admin:
                if not hmac.compare_digest(str(fields.get("csrf","")),self.activation_csrf()):
                    self.send_json({"ok":False,"error":"页面已失效，请刷新后重试"},403); return True
                if path.endswith("/create"):
                    value = self.activation_store().create(int(fields.get("userId","")),int(fields.get("days","")),
                        int(fields.get("maxDevices","")),fields.get("plan"))
                    self.activation_admin_page("授权码已生成，只显示这一次。",value["code"])
                else:
                    self.activation_store().revoke(int(fields.get("id","")))
                    self.activation_admin_page("授权已撤销。客户端下次联网续期时同步，未过期的离线凭证最多保留至原到期时间。")
                return True
            context = self.activation_context()
            token = context["token"](self.headers)
            user = context["user"](token)
            if not user:
                self.send_json({"ok":False,"error":"请先登录账号"},401); return True
            validate_request(fields.get("deviceId"),fields.get("nonce"))
            session_hash = context["session_hash"](token)
            with sqlite3.connect(context["database"]) as db:
                session = db.execute("select expires_at from mbs_sessions where token_hash=? and expires_at>?",(session_hash,time.time())).fetchone()
            if not session:
                self.send_json({"ok":False,"error":"登录已失效"},401); return True
            grant = self.activation_store().redeem(fields.get("code"),user,fields["deviceId"],fields["nonce"],
                session_hash,session[0],EditorLicenseIssuer(context["data_dir"]))
            self.send_json({"ok":True,**grant})
        except (ValueError,TypeError) as error:
            if admin: self.activation_admin_page(str(error),status=400)
            else: self.send_json({"ok":False,"error":str(error)},400)
        except (OSError,sqlite3.Error):
            self.send_json({"ok":False,"error":"授权服务暂时不可用，请稍后重试"},503)
        return True
