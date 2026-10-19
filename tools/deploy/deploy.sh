#!/usr/bin/env bash
# 一条命令部署 dev2（后端 + Postgres 库 + 后台网页 + 安装包下载）到云服务器。在盒子上运行，不在服务器上编译。
#
#   DEPLOY_HOST=101.132.74.32 tools/deploy/deploy.sh [命令]
#
# 命令：
#   deploy                 （默认）setup + release：首次自动准备服务器，然后发布当前代码
#   setup                  只做服务器准备（可重复运行）：用户、目录、库和角色、环境文件、systemd 服务、备份定时
#   release                构建并发布当前代码：上传 → 迁移 → 首次灌内容 / 建管理员 → 重启 → 健康检查（保留 3 个版本）
#   rollback [--with-db --yes]   回到上一版（默认不动数据库）
#   status                 健康检查（只读）
#   inspect                服务器概况（只读：端口、服务、内存、磁盘）
#   admin-password         显示服务器上保存的后台管理员账号和密码（root 才能读的文件）
#   reset-admin-password   重新生成后台管理员密码
#   backup                 立刻备份一次数据库
#   download-backup [目录]  把最新的一份备份下载到本机（默认 /workspace/.deploy/backups/）
#   publish-apk <目录>      上传并发布安装包（release_apk.sh 会调用）
# 登录方式、名字和端口见 remote_lib.sh 开头（密码只从环境变量读，不落盘、不进日志）。
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=remote_lib.sh
. "$HERE/remote_lib.sh"
trap close_ssh EXIT

# 把参数安全地拼进远程命令（没有参数时什么都不拼）
qargs() { [ $# -eq 0 ] || printf '%q ' "$@"; }

CMD="${1:-deploy}"
[ $# -gt 0 ] && shift
NODE_VERSION="${NODE_VERSION:-22.15.1}"
CACHE="${DEPLOY_CACHE:-/workspace/.deploy/cache}"
TOOLS_REMOTE="/opt/$APP_NAME/tools"

check_connection() {
  say "连接 $TARGET（端口 $DEPLOY_PORT）…"
  rssh "$SUDO true" || oops "登录失败，或者 $DEPLOY_USER 没有免密 sudo。"
}

# 服务器没有 Node 22 时才需要：本机下载、校验，再上传（服务器在国内，直接下载经常很慢）
node_tarball() {
  local arch="linux-x64" name base
  name="node-v$NODE_VERSION-$arch.tar.xz"
  mkdir -p "$CACHE"
  if [ ! -f "$CACHE/$name" ]; then
    base="https://nodejs.org/dist/v$NODE_VERSION"
    say "下载 $name …"
    curl -fsSL -o "$CACHE/$name.part" "$base/$name"
    curl -fsSL -o "$CACHE/SHASUMS256-$NODE_VERSION.txt" "$base/SHASUMS256.txt"
    (cd "$CACHE" && grep " $name\$" "SHASUMS256-$NODE_VERSION.txt" | sed "s|$name|$name.part|" | sha256sum -c --quiet) || oops "Node 安装包校验失败"
    mv "$CACHE/$name.part" "$CACHE/$name"
  fi
  echo "$CACHE/$name"
}

do_setup() {
  check_connection
  local up args=(--public-url "$DEPLOY_PUBLIC_URL")
  up="$(remote_tmpdir)"
  rsync_up "$HERE/" "$up/tools/" --exclude sim/
  if ! rssh "/usr/local/bin/node -v 2>/dev/null | grep -q '^v22\.'"; then
    say "服务器没有 Node 22，上传一个只给本服务用的 Node（不动系统的 node）…"
    rsync_up "$(node_tarball)" "$up/"
    args+=(--node-tarball "$up/node-v$NODE_VERSION-linux-x64.tar.xz")
  fi
  rroot "DEPLOY_DIR=$up/tools bash $up/tools/server/setup_server.sh $(printf '%q ' "${args[@]}"); rc=\$?; rm -rf $up; exit \$rc"
}

do_release() {
  local id build up
  id="$(date +%Y%m%d-%H%M%S)"
  build="${DEPLOY_BUILD_DIR:-/workspace/.deploy/build}/$id"
  RELEASE_ID="$id" "$HERE/build_release.sh" "$build"
  check_connection
  rssh "test -f /etc/$APP_NAME/backend.env || $SUDO test -f /etc/$APP_NAME/backend.env" || oops "服务器还没准备过，先运行 deploy.sh setup（或 deploy）。"
  # 上传到服务器上固定的暂存目录：下次发布只传有变化的部分（服务器上行很慢）
  local stage="/var/tmp/$APP_NAME-stage"
  up="$(remote_tmpdir)"
  say "上传版本 $id（$(du -sh "$build" | cut -f1)，只传有变化的部分）…"
  rroot "mkdir -p $stage && chmod 700 $stage"
  rsync_up "$build/" "$stage/"
  rroot "rm -rf $up && cp -a $stage $up && chown -R root:root $up && DEPLOY_DIR=$up/tools bash $up/tools/server/update_release.sh $up"
  rm -rf "$build"
  say "外网检查 $DEPLOY_PUBLIC_URL/healthz …"
  if curl -fsS -m 10 "$DEPLOY_PUBLIC_URL/healthz"; then echo; say "外网可以访问。"
  else say "外网访问不到 $DEPLOY_PUBLIC_URL（服务器本机正常的话，多半是云安全组没开放端口 $APP_PORT）。"; fi
}

case "$CMD" in
  deploy) do_setup; do_release ;;
  setup) do_setup ;;
  release) do_release ;;
  rollback) check_connection; rroot "bash $TOOLS_REMOTE/server/rollback.sh $(qargs "$@")" ;;
  status) check_connection; rroot "bash $TOOLS_REMOTE/healthcheck.sh" ;;
  inspect)
    check_connection
    rroot "uptime; free -m; df -h /; echo; ss -ltnp; echo; systemctl --no-pager --type=service --state=running list-units | grep -Ei 'xiuxian|postgres|nginx' || true" ;;
  admin-password) check_connection; rroot "cat /etc/$APP_NAME/admin-credentials" ;;
  reset-admin-password) check_connection; rroot "bash $TOOLS_REMOTE/server/reset_admin_password.sh $(qargs "$@")" ;;
  backup) check_connection; rroot "$TOOLS_REMOTE/backup_db.sh" ;;
  download-backup)
    check_connection
    dest="${1:-/workspace/.deploy/backups}"
    mkdir -p "$dest" && chmod 700 "$dest"
    latest="$(rroot "ls -1t /var/backups/$APP_NAME/*.dump | head -1")"
    [ -n "$latest" ] || oops "服务器上还没有备份。"
    tmp="$(remote_tmpdir)"
    rroot "cp $latest $tmp/ && chown $DEPLOY_USER $tmp/*"
    rsync_down "$tmp/$(basename "$latest")" "$dest/"
    rssh "rm -rf $tmp"
    say "已下载到 $dest/$(basename "$latest")" ;;
  publish-apk)
    src="${1:?用法：deploy.sh publish-apk <含 apk 和 latest.json 的目录>}"
    check_connection
    # 固定暂存目录：断了重跑只补没传完的部分
    stage="/var/tmp/$APP_NAME-apk-stage"
    rroot "mkdir -p $stage && chmod 700 $stage && find $stage -maxdepth 1 -name '*.apk' -mtime +2 -delete"
    for f in "$src"/*.apk; do upload_big "$f" "$stage"; done
    rsync_up "$src/latest.json" "$stage/"
    names=""; for f in "$src"/*.apk; do names+="$stage/$(basename "$f") "; done
    up="$(remote_tmpdir)"
    rroot "cp $stage/latest.json $names$up/ && chown -R root:root $up && bash $TOOLS_REMOTE/server/publish_apk.sh $up && rm -f $names" ;;
  *) sed -n '2,22p' "$0"; exit 2 ;;
esac
