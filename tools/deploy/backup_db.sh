#!/bin/sh
set -eu
# 每天备份本机库。上传到对象存储需要项目负责人配置 OSS，本脚本只写到本地。
OUT_DIR="${BACKUP_DIR:-/var/backups/xiuxian}"
mkdir -p "$OUT_DIR"
STAMP=$(date +%Y%m%d)
pg_dump -Fc "$DATABASE_URL" -f "$OUT_DIR/xiuxian-$STAMP.dump"
find "$OUT_DIR" -name 'xiuxian-*.dump' -mtime +14 -delete
echo "wrote $OUT_DIR/xiuxian-$STAMP.dump"
