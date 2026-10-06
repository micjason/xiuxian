# 后端

本目录是第一批后端：玩家注册登录、打开时结算、突破、配置草稿和发布、操作记录查询、修复入口。后台页面和手机客户端不在这里。公网服务器上已经装了 Node.js 22 和 PostgreSQL，这一批进程还没有部署上去。

本机测试可以连已经准备好的数据库。在 `backend/` 下：

```bash
export DATABASE_URL=postgres://...@127.0.0.1:5432/xiuxian
npm run db:migrate
npm test
```

创建第一个管理员没有网页入口。密码不要写进仓库：

```bash
ADMIN_USERNAME=... ADMIN_PASSWORD=... npm run admin:create
```

本地另起数据库时：

```bash
docker compose up -d
```

启动接口：

```bash
PORT=8080 npm run dev
```

默认只听本机 `127.0.0.1:8080`。
