# 后端

玩家注册登录、结算、突破、配置发布、操作记录和修复入口。本机开发见仓库根目录的 `docs/operations/local-dev.md`。

PostgreSQL 只监听本机。开发时用 `backend/docker-compose.yml` 起 `xiuxian_dev` 和 `xiuxian_test`，或直接运行 `tools/local/setup_local.sh`。后台的 `npm run dev` 默认把请求转到 `http://127.0.0.1:8080`，地址由 `VITE_API_PROXY` 覆盖。
