# Mbs 网页搜索

页面文件部署到 `/var/www/mbs-search/`；`search.py` 和 systemd 单元部署到 `/opt/mbs-search/` 和 `/etc/systemd/system/`。服务仅监听 `127.0.0.1:18768`。Nginx 将 `/sousuo/` 映射到页面、将 `/api/search` 代理到本机服务，并对该接口限流及关闭访问日志。上游是 Bing RSS，搜索依赖上游可用性。搜索关键词会发送给 Bing；打开的结果由客户端直接访问。
