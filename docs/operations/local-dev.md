# 本机开发

后端和后台只连本机。开发过程中不要访问云服务器地址。

**按步骤的完整清单（含 Mac、Docker、后台、Godot）见 [`docs/local_run_mac.md`](../local_run_mac.md)。** 下面是摘要：

1. 安装 Docker 和 Node 22。
2. 仓库根目录执行 `tools/local/setup_local.sh`：起 Postgres、建库 `xiuxian_dev` / `xiuxian_test`、`npm ci`、迁移、灌入原型内容并发布、创建管理员 `owner`（密码默认 `xiuxian-local-1`，可用 `ADMIN_USERNAME` / `ADMIN_PASSWORD` 改）。可重复运行。已有自己的 Postgres 时用 `SKIP_DOCKER=1`。
3. `cd backend && npm run dev`。接口在 `http://127.0.0.1:8080`，`/healthz` 可检查。
4. 另开终端：`cd admin && npm ci && npm run dev`。后台地址看终端 `Local:` 一行，请求转到本机后端。
5. Godot 4.7.2 标准版打开 `game/project.godot`，点运行。登录页「服务器地址」默认就是 `http://127.0.0.1:8080`。

补充管理员：`cd backend && ADMIN_USERNAME=名字 ADMIN_PASSWORD='至少八位' npm run admin:ensure`。

测试用 `npm test`，它连 `xiuxian_test`，不使用开发库。
