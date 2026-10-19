#!/usr/bin/env bash
# shellcheck disable=SC2012
# 服务器健康检查（只读）：deploy.sh status 远程运行。输出里没有任何密码。全部正常退出码 0。
set -uo pipefail
APP_NAME="${APP_NAME:-xiuxian-dev2}"
ENV_FILE="/etc/$APP_NAME/backend.env"
BACKUP_DIR="/var/backups/$APP_NAME"
SERVICE_NAME="$APP_NAME-api"
PORT="$(grep -m1 '^PORT=' "$ENV_FILE" 2>/dev/null | cut -d= -f2-)"
PORT="${PORT:-8090}"
bad=0
ok() { printf '  [正常] %s\n' "$*"; }
fail() { printf '  [异常] %s\n' "$*"; bad=$((bad + 1)); }
note() { printf '  [提示] %s\n' "$*"; }

echo "== $APP_NAME =="
if systemctl is-active --quiet "$SERVICE_NAME"; then ok "$SERVICE_NAME 在运行"; else fail "$SERVICE_NAME 没有运行（journalctl -u $SERVICE_NAME 看原因）"; fi
cur="$(readlink -f "/opt/$APP_NAME/current" 2>/dev/null || true)"
note "当前版本：$(cat "$cur/VERSION" 2>/dev/null || echo 无)；保留的版本：$(ls -1 "/opt/$APP_NAME/releases" 2>/dev/null | tr '\n' ' ')"
body="$(curl -fsS -m 5 "http://127.0.0.1:$PORT/healthz" 2>/dev/null || true)"
if printf '%s' "$body" | grep -q '"ok":true'; then ok "/healthz $body"; else fail "/healthz 没有正常返回：${body:-无响应}"; fi
code="$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:$PORT/" || true)"
if [ "$code" = "200" ]; then ok "后台网页 / 200"; else fail "后台网页 / 返回 ${code:-无}"; fi
code="$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:$PORT/download/latest.json" || true)"
if [ "$code" = "200" ]; then ok "/download/latest.json 200"; else note "/download/latest.json 返回 ${code:-无}（还没发布过安装包时正常）"; fi
rss="$(systemctl show -p MemoryCurrent --value "$SERVICE_NAME" 2>/dev/null || true)"
[ -n "$rss" ] && [ "$rss" != "[not set]" ] && note "服务内存 $((rss / 1024 / 1024)) MB"
avail="$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo)"
if [ "${avail:-0}" -lt 150 ]; then fail "整机可用内存只有 ${avail} MB"; else ok "整机可用内存 ${avail} MB"; fi
latest="$(ls -1t "$BACKUP_DIR"/*.dump 2>/dev/null | head -1 || true)"
if [ -z "$latest" ]; then note "还没有备份（每天 04:15 自动备份）"; else ok "最新备份 $(basename "$latest")"; fi
echo
[ "$bad" -eq 0 ] && { echo "结果：全部正常"; exit 0; }
echo "结果：有 $bad 项异常"; exit 1
