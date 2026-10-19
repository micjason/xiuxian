# 服务器

> dev2 已经上线，见 [`docs/deploy_online.md`](../deploy_online.md)。dev2 不用 nginx。下面是以后接域名和证书时的旧笔记，`tools/deploy/nginx/` 已删除。

备案和证书由项目负责人办理。完成前线上继续用现有 HTTP 地址，本文件只保留切换时要用的步骤。

1. 把 `tools/deploy/nginx/xiuxian.conf` 里的 `api.example.com` 换成已备案域名。
2. 用 certbot 申请证书并设置自动续期。
3. 确认 PostgreSQL 只监听 127.0.0.1。
4. 用 `tools/deploy/backup_db.sh` 每天备份。对象存储上传不在本次执行范围内。
5. 外部监控每分钟请求 `/healthz`。账号由项目负责人开通。
