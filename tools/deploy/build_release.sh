#!/usr/bin/env bash
# 在本机（盒子）上把后端和后台网页构建成一个可以直接上线的发布目录，不在 2G 内存的服务器上编译。
# 用法：build_release.sh <输出目录>          输出目录里会有：
#   backend/dist/*.js        esbuild 打包好的入口（server / migrate / ensure-admin / seed-if-empty）
#   backend/node_modules     只含生产依赖（npm ci --omit=dev；argon2 用自带的 linux-x64 预编译包）
#   backend/drizzle          数据库迁移文件
#   backend/RELEASE          版本号（/healthz 会带上）
#   admin-dist/              后台网页
#   tools/                   服务器端脚本（tools/deploy 的拷贝）
#   VERSION                  版本说明（git 提交）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:?用法：build_release.sh <输出目录>}"
RELEASE_ID="${RELEASE_ID:-$(date +%Y%m%d-%H%M%S)}"
log() { printf '\033[1;36m[构建]\033[0m %s\n' "$*"; }

rm -rf "$OUT"
mkdir -p "$OUT/backend/dist"
GIT_REV="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
DIRTY=""
if git -C "$ROOT" status --porcelain 2>/dev/null | grep -qv '^??'; then DIRTY="+未提交改动"; fi

log "后端：esbuild 打包（目标 node22）"
cd "$ROOT/backend"
[ -d node_modules ] || npm ci --no-audit --no-fund --loglevel=error
for entry in server:src/server.ts migrate:src/db/migrate.ts ensure-admin:src/scripts/ensure-admin.ts seed-if-empty:src/scripts/seed-prototype-if-empty.ts; do
  name="${entry%%:*}"
  src="${entry#*:}"
  npx esbuild "$src" --bundle --platform=node --target=node22 --format=esm --packages=external \
    --log-level=warning --outfile="$OUT/backend/dist/$name.js"
done
cp package.json package-lock.json "$OUT/backend/"
cp -r drizzle "$OUT/backend/drizzle"
printf '%s\n' "$RELEASE_ID" >"$OUT/backend/RELEASE"

log "后端：安装生产依赖（npm ci --omit=dev）"
(cd "$OUT/backend" && npm ci --omit=dev --ignore-scripts --no-audit --no-fund --loglevel=error)
# argon2 自带各平台预编译包，--ignore-scripts 后确认 linux-x64 的在
ls "$OUT/backend/node_modules/argon2/prebuilds/linux-x64/"*.node >/dev/null

log "后台网页：vite build"
cd "$ROOT/admin"
[ -d node_modules ] || npm ci --no-audit --no-fund --loglevel=error
npm run build --silent >/dev/null
cp -r dist "$OUT/admin-dist"

log "服务器脚本"
mkdir -p "$OUT/tools"
cp -r "$ROOT/tools/deploy/server" "$ROOT/tools/deploy/systemd" "$ROOT/tools/deploy/backup_db.sh" "$ROOT/tools/deploy/healthcheck.sh" "$OUT/tools/"
printf '%s %s%s\n' "$RELEASE_ID" "$GIT_REV" "$DIRTY" >"$OUT/VERSION"
log "完成：$OUT（$(du -sh "$OUT" | cut -f1)），版本 $(cat "$OUT/VERSION")"
