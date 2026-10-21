#!/usr/bin/env bash
# 重置后台管理员密码：随机生成，只写进 $ADMIN_CRED_FILE（root 才能读），不在终端输出里显示。
# 本机用 deploy.sh admin-password 下载成 0600 文件，脚本按文件路径读。
# 用法：reset_admin_password.sh [用户名，默认 owner]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
need_root
[ -L "$XIUXIAN_ROOT/current" ] || die "还没有部署过代码。"
USER_NAME="${1:-owner}"
PASS="$(rand_pass 20)"
NODE_BIN="$(env_get "$ENV_FILE" NODE_BIN)"
RES="$(ADMIN_USERNAME="$USER_NAME" ADMIN_PASSWORD="$PASS" ADMIN_RESET=1 run_in_env "$XIUXIAN_ROOT/current" "${NODE_BIN:-/usr/local/bin/node}" dist/ensure-admin.js | tail -1)"
case "$RES" in created|reset) ;; *) die "没有成功（结果：$RES）" ;; esac
PUBLIC_BASE_URL="$(env_get "$ENV_FILE" PUBLIC_BASE_URL)"
(umask 077; printf '后台管理员账号：%s\n后台管理员密码：%s\n网址：%s/\n' "$USER_NAME" "$PASS" "$PUBLIC_BASE_URL" >"$ADMIN_CRED_FILE")
chmod 600 "$ADMIN_CRED_FILE"
PASS=""
printf '\n后台管理员 %s 的密码已%s，只写在 %s（root 才能读），不在这里显示。\n在盒子上运行 deploy.sh admin-password 下载到本机 0600 文件。\n' "$USER_NAME" "$([ "$RES" = created ] && echo 创建 || echo 重置)" "$ADMIN_CRED_FILE"
