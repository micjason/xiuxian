#!/usr/bin/env bash
# 本机一键准备后端：起 Postgres（Docker）→ 建库 → 装依赖 → 迁移 → 灌入原型内容并发布 → 建后台管理员。
# 重复运行是安全的：库已存在不重建，已发布内容不覆盖，管理员已存在不改。
#
# 用法（在仓库根目录）：
#   tools/local/setup_local.sh
# 可选环境变量：
#   ADMIN_USERNAME  后台管理员用户名，默认 owner
#   ADMIN_PASSWORD  后台管理员密码，默认 xiuxian-local-1（至少 8 位，不能和用户名相同；只用于本机）
#   SKIP_DOCKER=1   不碰 Docker，直接用 DATABASE_URL 指向的 Postgres（自己已经有数据库时用）
#   DATABASE_URL    覆盖 backend/.env 里的数据库地址
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT/backend"

say() { printf '\n== %s\n' "$1"; }
die() { printf '\n[失败] %s\n' "$1" >&2; exit 1; }

command -v node >/dev/null || die "没找到 node。先装 Node 22（https://nodejs.org 或 brew install node@22）。"
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 20 ] || die "Node 版本太低（现在是 $(node -v)），需要 20.19 以上，建议 22。"
command -v npm >/dev/null || die "没找到 npm。"

if [ "${SKIP_DOCKER:-0}" != "1" ]; then
  say "1/6 启动 Postgres（Docker）"
  command -v docker >/dev/null || die "没找到 docker。装好并打开 Docker Desktop，或者自己有 Postgres 的话用 SKIP_DOCKER=1 重新运行。"
  docker info >/dev/null 2>&1 || die "Docker 没有运行。先打开 Docker Desktop，等菜单栏图标显示 running，再重新运行本脚本。"
  docker compose up -d
else
  say "1/6 跳过 Docker（SKIP_DOCKER=1），使用已有的 Postgres"
fi

say "2/6 准备 backend/.env"
if [ -f .env ]; then
  echo ".env 已存在，不改动"
else
  cp .env.example .env
  echo "已从 .env.example 生成 .env"
fi

say "3/6 安装后端依赖（npm ci）"
npm ci --no-audit --no-fund

say "4/6 等数据库就绪并建库"
ok=0
for i in $(seq 1 30); do
  if npm run --silent db:ensure; then ok=1; break; fi
  echo "数据库还没好，2 秒后重试（$i/30）…"
  sleep 2
done
[ "$ok" = "1" ] || die "连不上数据库。看 docs/local_run_mac.md 的「排错」：端口 5432 被占用 / Docker 没开 / DATABASE_URL 不对。"

say "5/6 数据库迁移 + 灌入原型内容并发布"
npm run --silent db:migrate
npm run --silent db:seed-prototype

say "6/6 创建后台管理员"
export ADMIN_USERNAME="${ADMIN_USERNAME:-owner}"
export ADMIN_PASSWORD="${ADMIN_PASSWORD:-xiuxian-local-1}"
result="$(npm run --silent admin:ensure | tail -1)"
echo "管理员 $ADMIN_USERNAME：$result"

cat <<MSG

全部完成。下一步：
  1) 起后端（保持这个终端开着）：  cd backend && npm run dev
  2) 看到 "Server listening at http://127.0.0.1:8080" 后，浏览器打开 http://127.0.0.1:8080/healthz 应显示 {"ok":true,...}
  3) 另开终端起后台：              cd admin && npm ci && npm run dev   → http://127.0.0.1:5173
  4) 后台登录账号：$ADMIN_USERNAME，密码见上面的 ADMIN_PASSWORD（默认 xiuxian-local-1）
MSG
