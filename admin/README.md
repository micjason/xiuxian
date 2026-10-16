# 后台管理

Vue 3 + Element Plus。本机运行：先起后端（`backend/` 下 `npm run dev`，默认 `http://127.0.0.1:8080`），再在这个目录执行 `npm ci && npm run dev`，打开终端里 `Local:` 那一行的地址（通常是 http://127.0.0.1:5173 ）。请求转到本机后端，后端换了端口用 `VITE_API_PROXY` 指定。

完整步骤（含建管理员账号）见仓库根目录 `docs/local_run_mac.md`。

页面：概览、玩家运营、游戏配置、发布中心、公告弹窗、系统。
