# dev2 上线（成鹏的云服务器 101.132.74.32）

## 现在线上有什么

| 用途 | 地址 |
|---|---|
| 后台 | http://101.132.74.32:8090/ （账号 owner） |
| 健康检查 | http://101.132.74.32:8090/healthz |
| 更新信息 | http://101.132.74.32:8090/download/latest.json |
| 安装包 | http://101.132.74.32:8090/download/xiuxian-dev2-<版本>-<号>.apk |

- 安卓包名 `com.micjason.xiuxian.dev2`，桌面名「修仙 测试版」，和旧版并存安装，不会覆盖旧版。
- 一个 Node 服务同时提供接口、后台网页和下载，没有 nginx。

## 和服务器上原有程序的关系（不动对方的东西）

| | 原有（成鹏的） | dev2（我们的） |
|---|---|---|
| 服务 | xiuxian-api（8080，80 端口的 python3） | xiuxian-dev2-api（8090） |
| 数据库 | xiuxian | xiuxian_dev2（单独的角色，最多 6 个连接，服务只用 4 个） |
| 目录 | /home/admin/xiuxian | /opt/xiuxian-dev2、/etc/xiuxian-dev2 |
| 备份 | — | /var/backups/xiuxian-dev2，每天 04:15，留 7 天 |

- 用服务器已有的 Node 22.15.1 和 PostgreSQL 16，没有装或升级任何软件，没改防火墙、iptables、swap。
- 服务内存上限 400 MB（整机 1.6 GB，和原有程序共用）。

## 需要成鹏提供的

1. SSH：root 密码或密钥。我们只从环境变量读密码，不写到文件里。
2. 安全组放行 TCP 8090 入方向。已放行。
3. 原有服务继续由成鹏自己管，我们不碰。

## 常用命令（在 box 上，仓库根目录）

先设好连接：`export DEPLOY_HOST=101.132.74.32 SERVER_SSH_PASSWORD=…`（也可以用 `DEPLOY_SSH_KEY=密钥路径`）。

| 要做的事 | 命令 |
|---|---|
| 发布当前代码（首次会自动准备服务器） | `tools/deploy/deploy.sh` |
| 看状态 | `tools/deploy/deploy.sh status` |
| 回到上一个版本 | `tools/deploy/rollback.sh`（连库一起回：`rollback.sh --with-db --yes`） |
| 取后台密码（写到本机 0600 文件，不显示） | `tools/deploy/deploy.sh admin-password [文件]`，默认 `/workspace/.deploy/admin-credentials.env`；脚本用 `ADMIN_CRED_FILE=<路径>` 读（`tools/deploy/admin_cred.mjs`） |
| 重置后台密码（新密码只写服务器文件，不显示） | `tools/deploy/deploy.sh reset-admin-password`，然后 `admin-password` 下载 |
| 立即备份 / 下载最新备份 | `deploy.sh backup` / `deploy.sh download-backup` |
| 出新安装包并发布 | `tools/deploy/release_apk.sh --notes "这次改了什么"`（强制更新加 `--force`） |

每次发布 `deploy.sh` 会：
1. 在 box 上打包；
2. 上传，只传有变化的部分；
3. 先备份数据库；
4. 迁移，内容为空时灌初始内容，第一次时建管理员；
5. 切换版本并重启，再做健康检查，不通过就自动切回上一版；
6. 只留最近 3 个版本。

`release_apk.sh` 会：
1. 版本号加 1；
2. 写入服务器地址 http://101.132.74.32:8090；
3. 用固定的密钥签名并核对；
4. 上传 APK 和 latest.json。

上传 APK 时会把文件切成块，用几条连接同时传，断了重跑会接着传。

## 应用内更新

- 游戏启动或回到前台时读 `/download/latest.json`，内容是 {versionCode, versionName, url, sha256, notes, force}。
- 发现更高的 versionCode 时，弹出「发现新版本 x.y.z」，按钮是「更新」和「稍后」。强制更新时只有「更新」。
- 下载时显示进度，核对 sha256 后调起系统安装器。失败了可以点「用浏览器下载」。

## 密码和密钥放在哪

- 后台管理员密码：服务器 `/etc/xiuxian-dev2/admin-credentials`，只有 root 能读。
- 数据库密码：服务器 `/etc/xiuxian-dev2/backend.env`，只有 root 能读。
- 安卓签名密钥：box `/workspace/secrets/android/xiuxian-dev2-release.keystore`，口令在同目录 `.pass`。备份在 `/workspace/.deploy/signing-backup/`。**这把钥匙丢了，就不能再给已装的测试版推送更新**，请另外离线保存一份。

## 风险

- 用的是 http 明文，没有域名和证书。安装包有 sha256 校验，但网络上能被看到内容。
- 内存紧：整机 1.6 GB，两套服务共用。
- 备份只存在同一台服务器的磁盘上。
- 签名密钥和它的备份都在 box 的同一块磁盘上。
- box 往服务器上传很慢（有时只有几十 KB/s），发一次 APK（87 MB）可能要几十分钟。玩家下载速度取决于服务器的出口带宽。
- 旧的 jsdelivr 更新渠道 dev2 不再使用。第一次必须手动装测试版。

## 凭据不进输出（2026-10-21 起）
- 后台密码、测试账号密码只按**文件路径**传：`ADMIN_CRED_FILE`（后台）、`XIUXIAN_TEST_ACCOUNT_FILE`（游戏测试账号），文件 0600；脚本自己读，不打印。
- `deploy.sh admin-password` 只写文件；`reset-admin-password` 和首次部署也不再在终端显示密码。
- 万一要看日志里的东西，先过 `tools/deploy/redact.sh`（半角「:」「=」和全角「：」「＝」都处理）。
