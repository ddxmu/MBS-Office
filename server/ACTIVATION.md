# Mbs 自有授权码服务接入

部署文件：`mbs_editor_licenses.py`、`mbs_activation_codes.py`、`mbs_activation_routes.py`。已有账号服务继续负责密码哈希、会话有效期和管理员认证。签名私钥只保存在服务端数据目录，客户端固定公钥校验。

处理器继承 `ActivationRoutes`，提供 `activation_context()` 字典：

```python
{
    "database": DB_PATH, "data_dir": DATA_DIR,
    "user": mbs_current_user, "token": mbs_bearer_token,
    "session_hash": mbs_session_hash, "page": page,
    "secret": secret,
}
```

在 GET 分发最前调用 `activation_get(urlparse(self.path))`；POST 分发最前调用 `activation_post(urlparse(self.path).path)`，返回真时结束处理。处理器保留已有 `is_admin`、`body_fields`、`send_json`、`send_html`、`redirect` 方法。

- `/admin/mbs-licenses`：管理员页面；创建与撤销使用 POST、来源检查和会话绑定的 CSRF。
- `/api/mbs/activation/redeem`：Bearer 会话；POST JSON 包含 `code`、`deviceId`、43 字符 base64url `nonce`；返回签名授权。
- `/api/mbs/activation/auto`：相同的 Bearer、设备与 nonce 校验；没有任何授权历史的账号首次联网激活时自动签发一年标准授权（默认 1 台设备）。已有账号选择有效且有设备名额的授权并在同一事务中绑定；不会为已到期、已撤销或设备超限的账号重复发放免费授权。响应签名包含 `activationState`：`active`、`expired`、`revoked` 或 `device_limit`。
- `/api/mbs/activation/status?deviceId=UUID`：当前账号当前设备的授权状态。
- 原 `/api/mbs/editor/license` 续期时，使用 `ActivationCodes(DB_PATH).for_device(user["id"], device_id)` 查询有效绑定；如存在，将签发到期时间限制为会话与授权码的较早到期时间，并把该对象作为 `issue(..., activation=activation)` 参数。不存在时沿用原有基础账号授权。

只保存高熵授权码的 SHA-256 与尾号，明文生成时显示一次。设备绑定在 SQLite 即时事务中计数，重复兑换同一设备不占额外名额。撤销在客户端下次联网续期时同步；离线凭证仍可使用至原签名到期时间。客户端不以未经签名的网页状态覆盖授权。

生成页面默认有效期为 365 天，可手动选择 1–365 天，从生成时开始计时。授权码到期时间与客户端短期签名凭证到期时间分开：短期凭证仍受会话及 30 天上限约束，客户端启动时及运行中每 5 分钟联网续期；续期不缩短授权码本身的有效期。

0.1.26 客户端的启动验证和定期续期使用自动激活接口；账号面板点击“激活”时，输入了新码则兑换，空白则重新同步网站授权。新账号需先注册并登录，授权和设备绑定均由服务端签发，客户端不自行生成授权。

生产服务于 2026-10-20 完成部署，原有 8 张表记录数量校验保持不变。服务端测试涵盖错误账号、过期、撤销、设备上限、并发兑换及管理页面 CSRF。Mbs 自有授权不替代原厂许可证。
