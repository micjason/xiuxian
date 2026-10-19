#!/usr/bin/env bash
# 服务器端脚本共用的变量和小函数。只被 source，不单独运行。全部在服务器上以 root 运行。
# shellcheck disable=SC2034

# 全部名字都可以改，默认是 dev2 这一套（和服务器上已有的 xiuxian-api / xiuxian 库完全分开）
APP_NAME="${APP_NAME:-xiuxian-dev2}"
XIUXIAN_ROOT="${XIUXIAN_ROOT:-/opt/$APP_NAME}"
XIUXIAN_ETC="${XIUXIAN_ETC:-/etc/$APP_NAME}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/$APP_NAME}"
XIUXIAN_USER="${XIUXIAN_USER:-$APP_NAME}"
SERVICE_NAME="${SERVICE_NAME:-$APP_NAME-api}"
DB_NAME="${DB_NAME:-xiuxian_dev2}"
DB_USER="${DB_USER:-xiuxian_dev2}"
DB_POOL_MAX="${DB_POOL_MAX:-4}"
APP_PORT="${APP_PORT:-8090}"
APP_HOST="${APP_HOST:-0.0.0.0}"
KEEP_RELEASES="${KEEP_RELEASES:-3}"
ENV_FILE="$XIUXIAN_ETC/backend.env"
ADMIN_CRED_FILE="$XIUXIAN_ETC/admin-credentials"
DOWNLOAD_DIR="$XIUXIAN_ROOT/shared/download"
NODE_BIN="${NODE_BIN:-/usr/local/bin/node}"
CRON_FILE="/etc/cron.d/$APP_NAME-backup"
# 服务器上常驻的一份脚本（每次发布刷新），回滚、重置密码、备份、发布安装包都用这里的
TOOLS_DIR="$XIUXIAN_ROOT/tools"
# 本脚本所在的 tools 目录（里面有 systemd 模板）
DEPLOY_DIR="${DEPLOY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

log() { printf '\033[1;32m[服务器]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[注意]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[出错]\033[0m %s\n' "$*" >&2; exit 1; }

need_root() { [ "$(id -u)" -eq 0 ] || die "要用 root 运行（deploy.sh 会自动用 sudo）。"; }

health_url() { echo "http://127.0.0.1:$(env_get "$ENV_FILE" PORT)/healthz"; }

rand_hex() { openssl rand -hex "${1:-24}"; }
rand_pass() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c1-"${1:-20}"; }

env_get() { # env_get 文件 键
  [ -f "$1" ] || return 0
  grep -m1 "^$2=" "$1" | cut -d= -f2- || true
}
env_set() { # env_set 文件 键 值   （替换或追加；保持文件权限）
  local f="$1" k="$2" v="$3" tmp
  tmp="$(mktemp)"
  { grep -v "^${k}=" "$f" 2>/dev/null || true; } >"$tmp"
  printf '%s=%s\n' "$k" "$v" >>"$tmp"
  cat "$tmp" >"$f"
  rm -f "$tmp"
}
env_default() { # 只在没有这个键时才写
  if [ -z "$(env_get "$1" "$2")" ]; then env_set "$1" "$2" "$3"; fi
}

# 把模板里的 @名字@ 换成值。参数：模板 输出 名=值 ...（值里不能有 | 和换行）
render_template() {
  local src="$1" dst="$2" tmp pair k v
  shift 2
  tmp="$(mktemp)"
  cp "$src" "$tmp"
  for pair in "$@"; do
    k="${pair%%=*}"
    v="${pair#*=}"
    sed -i "s|@${k}@|${v}|g" "$tmp"
  done
  if grep -q '@[A-Z_]*@' "$tmp"; then
    rm -f "$tmp"
    die "模板 $src 里还有没替换的占位符"
  fi
  install -m 0644 "$tmp" "$dst"
  rm -f "$tmp"
}

wait_healthy() { # wait_healthy URL 秒数 [期望出现的文字]
  local url="$1" secs="${2:-40}" want="${3:-}" i=0 body
  while [ "$i" -lt "$secs" ]; do
    body="$(curl -fsS -m 3 "$url" 2>/dev/null || true)"
    if [ -n "$body" ] && { [ -z "$want" ] || printf '%s' "$body" | grep -qF "$want"; }; then return 0; fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

service_logs() { journalctl -u "$SERVICE_NAME" -n 40 --no-pager 2>/dev/null || true; }

# 带着线上环境变量，在某个发布目录的 backend 里跑命令
run_in_env() { # run_in_env 发布目录 命令...
  local rel="$1"
  shift
  (
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
    cd "$rel/backend" || exit 1
    "$@"
  )
}

render_systemd_unit() {
  render_template "$DEPLOY_DIR/systemd/app-api.service.template" "/etc/systemd/system/$SERVICE_NAME.service" \
    "ROOT=$XIUXIAN_ROOT" "ENV_FILE=$ENV_FILE" "USER=$XIUXIAN_USER" "NODE_BIN=$NODE_BIN" "APP_NAME=$APP_NAME"
  systemctl daemon-reload
}

# 原子地把某个链接（current / previous）指向目录
point_link() { # point_link 链接 目标
  local tmp="$1.new.$$"
  ln -sfn "$2" "$tmp"
  mv -T "$tmp" "$1"
}
