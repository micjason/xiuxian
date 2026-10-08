# 本机开发

后端和后台只连本机。开发过程中不要访问云服务器地址。

1. 安装 Docker。
2. 在 `backend/` 执行 `docker compose up -d`。这会创建 `xiuxian_dev` 和 `xiuxian_test`。
3. `cp .env.example .env`。
4. `npm install`。
5. `npm run db:migrate`。
6. `npm run admin:create -- --username owner --password '至少八位且不同于用户名'`。角色参数在后续任务里补上。
7. `npm run dev`。接口在 `http://127.0.0.1:8080`。
8. 另开终端，进入 `admin/`，`npm install` 然后 `npm run dev`。后台在 `http://127.0.0.1:5173`，请求转到本机后端。
9. Godot 打开 `game/`，按播放。手机端地址以后由工程配置指定，默认也是本机。

测试用 `npm test`，它连 `xiuxian_test`，不使用开发库。
