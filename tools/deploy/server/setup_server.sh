#!/usr/bin/env bash
# 服务器一次性准备（可以重复运行：已有的部分跳过，已有的数据库密码、管理员不改）。root 运行，由 deploy.sh 远程调用。
# 只新建属于 $APP_NAME（默认 xiuxian-dev2）的东西：
#   系统用户 / /opt/$APP_NAME / /etc/$APP_NAME（root 才能读的环境文件）/ 新库和新角色 / systemd 服务 / 备份定时。
# 不装、不升级任何软件包，不改 swap、防火墙、nginx、iptables，不碰别的服务、别的库和端口。
# 依赖服务器上已有的：Node 22（/usr/local/bin/node；没有就用 --node-tarball 解压到 /opt/$APP_NAME/node，不动系统的 node）、
#                   Postgres 16（本机 5432，运行中）。
# 用法：setup_server.sh --public-url http://101.132.74.32:8090 [--node-tarball 路径]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

PUBLIC_URL=""
NODE_TARBALL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --public-url) PUBLIC_URL="$2"; shift 2 ;;
    --node-tarball) NODE_TARBALL="$2"; shift 2 ;;
    *) die "不认识的参数：$1" ;;
  esac
done
[ -n "$PUBLIC_URL" ] || die "需要 --public-url（例如 http://101.132.74.32:8090）"
PUBLIC_URL="${PUBLIC_URL%/}"
need_root

OUR_MARK="Xiuxian game backend ($APP_NAME)"

# ---------------------------------------------------------------- 1. 体检（只读）
check_system() {
  # shellcheck disable=SC1091
  . /etc/os-release
  [ "${ID:-}" = "ubuntu" ] || warn "系统是 ${PRETTY_NAME:-未知}，脚本按 Ubuntu 24.04 写的。"
  command -v psql >/dev/null || die "服务器上没有 psql（Postgres 客户端）。本脚本不装软件包。"
  runuser -u postgres -- psql -X -Atqc 'select 1' postgres >/dev/null || die "本机 Postgres 没在运行或连不上。"
  local unit="/etc/systemd/system/$SERVICE_NAME.service"
  if [ -f "$unit" ] && ! grep -qF "$OUR_MARK" "$unit"; then
    die "$unit 已经存在而且不是本脚本建的，换一个 APP_NAME。"
  fi
  # 端口：只能是空的，或者是我们自己的服务在用
  local who
  who="$(ss -ltnpH "sport = :$APP_PORT" 2>/dev/null || true)"
  if [ -n "$who" ] && ! systemctl is-active --quiet "$SERVICE_NAME"; then
    die "端口 $APP_PORT 已经被别的程序占用：
$who
换一个 APP_PORT。"
  fi
  if [ -e "$CRON_FILE" ] && ! grep -q "$APP_NAME" "$CRON_FILE"; then die "$CRON_FILE 已存在且不是本脚本建的。"; fi
}

# ---------------------------------------------------------------- 2. Node（优先用已有的 22 版）
ensure_node() {
  if [ -x "$NODE_BIN" ] && "$NODE_BIN" -v | grep -q '^v22\.'; then
    log "使用服务器已有的 Node $("$NODE_BIN" -v)（$NODE_BIN）。"
    return 0
  fi
  local own="$XIUXIAN_ROOT/node/bin/node"
  if [ -x "$own" ] && "$own" -v | grep -q '^v22\.'; then NODE_BIN="$own"; log "使用自带的 Node $("$own" -v)。"; return 0; fi
  if [ -z "$NODE_TARBALL" ] || [ ! -f "$NODE_TARBALL" ]; then die "没有 Node 22，也没有收到 --node-tarball。"; fi
  log "解压 Node 到 $XIUXIAN_ROOT/node（只给本服务用，不动系统的 node）…"
  mkdir -p "$XIUXIAN_ROOT/node"
  tar -C "$XIUXIAN_ROOT/node" --strip-components=1 -xJf "$NODE_TARBALL"
  NODE_BIN="$own"
}

# ---------------------------------------------------------------- 3. 用户、目录、常驻脚本
ensure_user_and_dirs() {
  if ! id "$XIUXIAN_USER" >/dev/null 2>&1; then
    log "新建系统用户 $XIUXIAN_USER（不能登录）"
    useradd --system --home-dir "$XIUXIAN_ROOT" --no-create-home --shell /usr/sbin/nologin "$XIUXIAN_USER"
  fi
  mkdir -p "$XIUXIAN_ROOT"/{releases,shared/var,shared/apks} "$DOWNLOAD_DIR" "$XIUXIAN_ETC" "$BACKUP_DIR" "$TOOLS_DIR"
  chmod 700 "$XIUXIAN_ETC" "$BACKUP_DIR"
  chmod 755 "$XIUXIAN_ROOT" "$XIUXIAN_ROOT/releases" "$XIUXIAN_ROOT/shared" "$DOWNLOAD_DIR"
  chown -R "$XIUXIAN_USER:$XIUXIAN_USER" "$XIUXIAN_ROOT/shared/var" "$XIUXIAN_ROOT/shared/apks"
  rsync -a --delete "$DEPLOY_DIR/" "$TOOLS_DIR/"
  chown -R root:root "$TOOLS_DIR"
  chmod -R go-w "$TOOLS_DIR"
}

# ---------------------------------------------------------------- 4. 数据库（新库、新角色）和环境文件
ensure_database() {
  local url pass
  url="$(env_get "$ENV_FILE" DATABASE_URL)"
  if [ -n "$url" ]; then
    if psql "$url" -Atqc 'select 1' >/dev/null 2>&1; then log "数据库 $DB_NAME 已存在且能连上，保留现有密码。"; return 0; fi
    die "环境文件里的数据库地址连不上。要重置：删掉 $ENV_FILE 里 DATABASE_URL 那一行再运行（不删数据）。"
  fi
  case "$DB_NAME$DB_USER" in *[!a-z0-9_]*) die "库名 / 角色名只能用小写字母、数字、下划线。" ;; esac
  pass="$(rand_hex 24)"
  log "创建角色 $DB_USER 和数据库 $DB_NAME（随机密码，只写进 $ENV_FILE）…"
  # 密码经标准输入交给 psql，不出现在进程列表和日志里
  runuser -u postgres -- psql -X -q -v ON_ERROR_STOP=1 postgres <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_USER') THEN
    CREATE ROLE $DB_USER LOGIN PASSWORD '$pass' CONNECTION LIMIT 6;
  ELSE
    ALTER ROLE $DB_USER LOGIN PASSWORD '$pass';
  END IF;
END \$\$;
SQL
  if [ -z "$(runuser -u postgres -- psql -X -Atc "select 1 from pg_database where datname='$DB_NAME'" postgres)" ]; then
    runuser -u postgres -- psql -X -q -v ON_ERROR_STOP=1 -c "CREATE DATABASE $DB_NAME OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0" postgres
  fi
  runuser -u postgres -- psql -X -q -v ON_ERROR_STOP=1 -c "REVOKE CONNECT, TEMP ON DATABASE $DB_NAME FROM PUBLIC" postgres
  touch "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  env_set "$ENV_FILE" DATABASE_URL "postgres://$DB_USER:$pass@127.0.0.1:5432/$DB_NAME"
}

ensure_env_file() {
  touch "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  chown root:root "$ENV_FILE"
  env_default "$ENV_FILE" NODE_ENV production
  env_set "$ENV_FILE" HOST "$APP_HOST"
  env_set "$ENV_FILE" PORT "$APP_PORT"
  env_set "$ENV_FILE" PUBLIC_BASE_URL "$PUBLIC_URL"
  env_set "$ENV_FILE" APK_BASE_URL "$PUBLIC_URL"
  env_set "$ENV_FILE" CORS_ORIGINS "$PUBLIC_URL"
  env_default "$ENV_FILE" ENABLE_GM_TOOLS false
  env_default "$ENV_FILE" LOG_LEVEL info
  env_set "$ENV_FILE" DB_POOL_MAX "$DB_POOL_MAX"
  env_set "$ENV_FILE" APK_DIR "$XIUXIAN_ROOT/shared/apks"
  env_set "$ENV_FILE" STATIC_ADMIN_DIR "$XIUXIAN_ROOT/current/admin-dist"
  env_set "$ENV_FILE" STATIC_DOWNLOAD_DIR "$DOWNLOAD_DIR"
  env_set "$ENV_FILE" NODE_BIN "$NODE_BIN"
}

# ---------------------------------------------------------------- 5. 服务、备份定时
install_service() {
  render_systemd_unit
  systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
}

install_backup_cron() {
  cat >"$CRON_FILE" <<CRON
# $APP_NAME：每天 04:15（服务器时间）备份数据库 $DB_NAME 到 $BACKUP_DIR，保留 7 天。日志 /var/log/$APP_NAME-backup.log
SHELL=/bin/bash
15 4 * * * root APP_NAME=$APP_NAME RETAIN_DAYS=7 $TOOLS_DIR/backup_db.sh >>/var/log/$APP_NAME-backup.log 2>&1
CRON
  chmod 644 "$CRON_FILE"
}

log "准备 $APP_NAME（端口 $APP_PORT，库 $DB_NAME，公网地址 $PUBLIC_URL）"
check_system
ensure_node
ensure_user_and_dirs
ensure_database
ensure_env_file
install_service
install_backup_cron
log "系统部分完成。"
