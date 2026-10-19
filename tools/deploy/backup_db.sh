#!/usr/bin/env bash
# 备份 $APP_NAME（默认 xiuxian-dev2）自己的数据库到带时间的文件，并清理旧备份。只备份这一个库。
# 用法：backup_db.sh                          （每天由 /etc/cron.d/$APP_NAME-backup 调用）
#       BACKUP_LABEL=pre-update backup_db.sh   （更新前备份，文件名带标签）
# 环境变量：APP_NAME、DATABASE_URL（不设就读 /etc/$APP_NAME/backend.env）、BACKUP_DIR（默认 /var/backups/$APP_NAME）、
#           RETAIN_DAYS（默认 7）、KEEP_MIN（无论多旧都至少保留最新几份，默认 3）。
# 最后一行输出 "wrote <文件路径>"。备份文件只有 root 能读（里面有玩家数据和密码哈希）。
# 备份在服务器本机磁盘上：服务器坏了备份也没了，要定期用 deploy.sh download-backup 拉一份回来。
set -euo pipefail
APP_NAME="${APP_NAME:-xiuxian-dev2}"
ENV_FILE="${ENV_FILE:-/etc/$APP_NAME/backend.env}"
if [ -z "${DATABASE_URL:-}" ] && [ -f "$ENV_FILE" ]; then
  DATABASE_URL="$(grep -m1 '^DATABASE_URL=' "$ENV_FILE" | cut -d= -f2-)"
fi
: "${DATABASE_URL:?没有 DATABASE_URL（也没找到 $ENV_FILE）}"
OUT_DIR="${BACKUP_DIR:-/var/backups/$APP_NAME}"
LABEL="${BACKUP_LABEL:-daily}"
RETAIN_DAYS="${RETAIN_DAYS:-7}"
KEEP_MIN="${KEEP_MIN:-3}"

umask 077
mkdir -p "$OUT_DIR"
avail_mb="$(df -Pm "$OUT_DIR" | awk 'NR==2 {print $4}')"
if [ "${avail_mb:-0}" -lt 300 ]; then
  echo "磁盘剩余只有 ${avail_mb} MB，不做备份。" >&2
  exit 1
fi
STAMP="$(date +%Y%m%d-%H%M%S)"
FINAL="$OUT_DIR/$APP_NAME-$STAMP-$LABEL.dump"
TMP="$FINAL.partial"
trap 'rm -f "$TMP"' EXIT
pg_dump -Fc "$DATABASE_URL" -f "$TMP"
pg_restore --list "$TMP" >/dev/null   # 能列出目录才算好备份
mv "$TMP" "$FINAL"
trap - EXIT

# 超过 RETAIN_DAYS 天的删掉，但无论如何保留最新 KEEP_MIN 份
# shellcheck disable=SC2012
ls -1t "$OUT_DIR"/"$APP_NAME"-*.dump 2>/dev/null | tail -n +"$((KEEP_MIN + 1))" | while IFS= read -r f; do
  if [ -n "$(find "$f" -mtime +"$((RETAIN_DAYS - 1))" -print 2>/dev/null)" ]; then rm -f "$f"; fi
done
echo "wrote $FINAL"
