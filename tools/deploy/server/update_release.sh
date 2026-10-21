#!/usr/bin/env bash
# 部署一个新版本（首次和以后每次都用它）。root 运行，参数是 deploy.sh 上传好的目录：
#   update_release.sh <上传目录>     目录里：backend/（dist + node_modules + drizzle + RELEASE）、admin-dist/、tools/、VERSION
# 流程：加锁 → 摆好 releases/<版本> → 更新前备份 → 迁移 → 首次灌内容 → 首次建管理员 → 切 current → 重启 → 健康检查
#       （失败自动切回上一版）→ 只保留最近 $KEEP_RELEASES 个版本。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

[ $# -ge 1 ] || die "用法：update_release.sh <上传目录>"
INCOMING="$(cd "$1" && pwd)"
need_root
[ -f "$ENV_FILE" ] || die "没有 $ENV_FILE，要先运行 setup_server.sh（deploy.sh 会自动先运行）。"
[ -f "$INCOMING/backend/dist/server.js" ] || die "$INCOMING/backend 不完整（缺 dist/server.js）。"
[ -f "$INCOMING/admin-dist/index.html" ] || die "$INCOMING/admin-dist 不完整（缺 index.html）。"
NODE_BIN="$(env_get "$ENV_FILE" NODE_BIN)"
NODE_BIN="${NODE_BIN:-/usr/local/bin/node}"

exec 9>"$XIUXIAN_ROOT/.deploy.lock"
flock -n 9 || die "另一个部署正在进行（$XIUXIAN_ROOT/.deploy.lock）。"

ID="$(cat "$INCOMING/backend/RELEASE")"
REL="$XIUXIAN_ROOT/releases/$ID"
CUR="$XIUXIAN_ROOT/current"
PREV_TARGET=""
[ -L "$CUR" ] && PREV_TARGET="$(readlink -f "$CUR")"
[ -d "$PREV_TARGET/backend" ] || PREV_TARGET=""
PUBLIC_BASE_URL="$(env_get "$ENV_FILE" PUBLIC_BASE_URL)"
HEALTH="$(health_url)"

# ---- 1. 摆好新目录 ----
[ "$REL" != "$PREV_TARGET" ] || die "版本 $ID 已经是当前版本。"
rm -rf "$REL"
mkdir -p "$REL"
mv "$INCOMING/backend" "$INCOMING/admin-dist" "$REL/"
cp "$INCOMING/VERSION" "$REL/VERSION"
ln -sfn "$XIUXIAN_ROOT/shared/var" "$REL/backend/var"
chown -R root:root "$REL"
chmod -R go-w,a+rX "$REL"
# 常驻脚本跟着版本一起更新
rsync -a --delete "$INCOMING/tools/" "$TOOLS_DIR/"
chown -R root:root "$TOOLS_DIR"
log "版本 $ID（$(cat "$REL/VERSION")）"

# ---- 2. 更新前备份（不是首次）----
if [ -n "$PREV_TARGET" ]; then
  log "更新前备份数据库…"
  out="$(APP_NAME="$APP_NAME" BACKUP_LABEL=pre-update "$TOOLS_DIR/backup_db.sh")"
  printf '%s\n' "$out" | sed -n 's/^wrote //p' | tail -1 >"$REL/PRE_UPDATE_BACKUP"
  log "$(tail -1 <<<"$out")"
fi

# ---- 3. 迁移、首次灌内容、首次管理员（用新版本的代码）----
log "数据库迁移…"
run_in_env "$REL" "$NODE_BIN" dist/migrate.js
log "内容：只在还没发布过时灌入原型 v1.2 并发布第 1 版…"
run_in_env "$REL" "$NODE_BIN" dist/seed-if-empty.js

ADMIN_USER="${ADMIN_USERNAME:-owner}"
NEW_ADMIN_PASSWORD=""
if [ ! -f "$ADMIN_CRED_FILE" ]; then
  NEW_ADMIN_PASSWORD="$(rand_pass 20)"
  # 密码只放在环境变量里（不是命令行参数），ps 看不到
  RES="$(ADMIN_USERNAME="$ADMIN_USER" ADMIN_PASSWORD="$NEW_ADMIN_PASSWORD" run_in_env "$REL" "$NODE_BIN" dist/ensure-admin.js | tail -1)"
  if [ "$RES" = "created" ]; then
    (umask 077; printf '后台管理员账号：%s\n后台管理员密码：%s\n网址：%s/\n' "$ADMIN_USER" "$NEW_ADMIN_PASSWORD" "$PUBLIC_BASE_URL" >"$ADMIN_CRED_FILE")
    chmod 600 "$ADMIN_CRED_FILE"
  else
    NEW_ADMIN_PASSWORD=""
    warn "后台账号 $ADMIN_USER 已经存在，没有改密码。忘了就运行 deploy.sh reset-admin-password。"
  fi
fi

# ---- 4. 切换、重启、健康检查 ----
point_link "$CUR" "$REL"
chown -R "$XIUXIAN_USER:$XIUXIAN_USER" "$XIUXIAN_ROOT/shared/var" "$XIUXIAN_ROOT/shared/apks"
NODE_BIN="$NODE_BIN" render_systemd_unit
log "重启 $SERVICE_NAME …"
systemctl restart "$SERVICE_NAME"
if ! wait_healthy "$HEALTH" 45 "\"version\":\"$ID\""; then
  warn "新版本 45 秒内没有通过健康检查，最后的日志："
  service_logs
  if [ -n "$PREV_TARGET" ]; then
    point_link "$CUR" "$PREV_TARGET"
    systemctl restart "$SERVICE_NAME"
    if wait_healthy "$HEALTH" 30; then warn "已自动回到上一版 $(basename "$PREV_TARGET")，服务正常。"; else warn "上一版也没起来！"; fi
  fi
  exit 1
fi
[ -n "$PREV_TARGET" ] && point_link "$XIUXIAN_ROOT/previous" "$PREV_TARGET"

# ---- 5. 只保留最近 $KEEP_RELEASES 个版本（当前和上一版永远不删）----
cur_real="$(readlink -f "$CUR")"
prev_real="$(readlink -f "$XIUXIAN_ROOT/previous" 2>/dev/null || true)"
# shellcheck disable=SC2012
ls -1dt "$XIUXIAN_ROOT"/releases/*/ 2>/dev/null | sed 's:/$::' | tail -n +"$((KEEP_RELEASES + 1))" | while IFS= read -r old; do
  if [ "$old" != "$cur_real" ] && [ "$old" != "$prev_real" ]; then log "删除旧版本 $(basename "$old")"; rm -rf "$old"; fi
done
rm -rf "$INCOMING"

log "完成：当前版本 $ID。$(curl -fsS -m 3 "$HEALTH")"
if [ -n "$NEW_ADMIN_PASSWORD" ]; then
  # 密码不进终端输出：只写在服务器 $ADMIN_CRED_FILE（root 可读），本机用 deploy.sh admin-password 下载成 0600 文件
  log "已创建后台管理员 $ADMIN_USER，密码只写在服务器 $ADMIN_CRED_FILE。在盒子上运行 deploy.sh admin-password 下载到本机 0600 文件（不显示）。"
  NEW_ADMIN_PASSWORD=""
fi
