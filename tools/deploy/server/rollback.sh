#!/usr/bin/env bash
# 回到上一个版本（代码 + 后台网页；/opt/$APP_NAME/previous 指向的目录）。再运行一次等于“前滚”回来。
# 默认不动数据库（迁移一般只是加表加列，旧代码能继续用）。
# 新版本的迁移和旧代码不兼容时加 --with-db --yes：用“更新前自动备份”恢复数据库，会丢掉之后产生的所有玩家数据。
# 用法：rollback.sh [--with-db --yes]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
WITH_DB=0
YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --with-db) WITH_DB=1; shift ;;
    --yes) YES=1; shift ;;
    *) die "不认识的参数：$1" ;;
  esac
done
need_root
CUR="$XIUXIAN_ROOT/current"
PREV="$XIUXIAN_ROOT/previous"
[ -L "$CUR" ] || die "还没有部署过。"
[ -L "$PREV" ] || die "没有上一版（只部署过一次）。"
CUR_DIR="$(readlink -f "$CUR")"
PREV_DIR="$(readlink -f "$PREV")"
[ -d "$PREV_DIR/backend" ] || die "上一版目录 $PREV_DIR 不存在了。"
exec 9>"$XIUXIAN_ROOT/.deploy.lock"
flock -n 9 || die "有部署正在进行。"

if [ "$WITH_DB" = "1" ]; then
  [ -f "$CUR_DIR/PRE_UPDATE_BACKUP" ] || die "当前版本没有「更新前备份」记录，不能恢复数据库。"
  DUMP="$(cat "$CUR_DIR/PRE_UPDATE_BACKUP")"
  [ -f "$DUMP" ] || die "备份文件 $DUMP 不存在。"
  [ "$YES" = "1" ] || die "恢复数据库会丢掉 $(basename "$DUMP") 之后的所有玩家数据。确认请加 --yes。"
  log "先给现在的数据库做一份保险备份…"
  APP_NAME="$APP_NAME" BACKUP_LABEL=pre-rollback "$TOOLS_DIR/backup_db.sh"
  systemctl stop "$SERVICE_NAME"
  log "从 $DUMP 恢复数据库 $DB_NAME …"
  pg_restore --clean --if-exists --no-owner --no-privileges --exit-on-error -d "$(env_get "$ENV_FILE" DATABASE_URL)" "$DUMP"
fi
log "回滚：$(basename "$CUR_DIR") → $(basename "$PREV_DIR")"
point_link "$CUR" "$PREV_DIR"
point_link "$PREV" "$CUR_DIR"
systemctl restart "$SERVICE_NAME"
if wait_healthy "$(health_url)" 45 "\"version\":\"$(cat "$PREV_DIR/backend/RELEASE")\""; then
  log "回滚完成，当前版本 $(basename "$PREV_DIR")。$(curl -fsS -m 3 "$(health_url)")"
else
  service_logs
  die "回滚后服务没起来。"
fi
