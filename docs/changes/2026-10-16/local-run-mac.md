# 本地运行清单（Mac）与一键准备脚本

云服务器部署已取消；Chengpeng 改为在自己的 Mac 上本地运行：后端 + Postgres（Docker）、后台网页本地 dev、Godot 编辑器里直接运行游戏。

## 新增 / 改动
- `docs/local_run_mac.md`：Mac 上照着做的清单（后端、后台含建管理员、Godot 4.7.2 打开工程运行并连本地后端、排错、验证情况）。盒子上的副本：`/workspace/local_run_checklist_mac.md`。
- `tools/local/setup_local.sh`：一条命令起 Postgres（`docker compose up -d`）→ 生成 `backend/.env` → `npm ci` → 建库 → 迁移 → 灌入原型 v1.2 内容并发布 → 建管理员。可重复运行；`SKIP_DOCKER=1` 用已有 Postgres。
- `backend/src/scripts/ensure-database.ts`（`npm run db:ensure`）：库不存在就建（含 `xiuxian_test`）。
- `backend/src/scripts/seed-prototype-if-empty.ts`（`npm run db:seed-prototype`）：只在还没发布过内容时灌入并发布；已发布就跳过（`seed-prototype.ts` 会清空重写，不能直接重复跑）。`SEED_FORCE=1` 才强制重写。
- `backend/src/scripts/ensure-admin.ts`（`npm run admin:ensure`）：账号密码走环境变量；已存在不动，`ADMIN_RESET=1` 才改密码。
- 后端新增可选环境变量 `HOST`（默认 `0.0.0.0`，行为不变）；`.env.example` 里设成 `127.0.0.1`，本地运行只有本机能访问。
- `admin/README.md`、`docs/operations/local-dev.md`、`backend/README.md`：删掉写着“请求转到云服务器 101.132.74.32”的过期说明，改成本地步骤（`local-dev.md` 里旧的 `admin:create -- --username` 用法其实不能用）。
- 顺手修了 3 处 lint 报错（未使用的 import / 变量：`ops-content.ts`、`loop/actions.ts`、`scripts/sim-random.ts`），不改行为，否则 CI 的 lint 会失败。

## 没有做
- 云部署相关的未完成改动（`app.ts` 的反向代理、`tools/deploy/*` 新脚本等）已 `git stash`（名称 `deploy-wip-cancelled`），没有进仓库。
- `.gitattributes` 仍把图片/字体标成 Git LFS，但文件是普通提交；没有处理（盒子没有 git-lfs）。

## 验证
见 `docs/local_run_mac.md` 第 5 节。没验证：Mac、Docker 实际运行、Godot 图形编辑器里点运行、真机。
