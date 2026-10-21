#!/usr/bin/env bash
# 盒子（本机）这一侧的 SSH 小工具，被 deploy.sh / release_apk.sh source。
# 连接参数全部来自环境变量：
#   DEPLOY_HOST          服务器地址（必填，例如 101.132.74.32）
#   DEPLOY_USER          登录用户（默认 root；不是 root 时用 sudo -n，需要免密 sudo）
#   DEPLOY_PORT          SSH 端口（默认 22）
#   DEPLOY_SSH_KEY       私钥路径（用密钥登录时）
#   DEPLOY_PASSWORD_ENV  存放 SSH 密码的环境变量名（默认 SERVER_SSH_PASSWORD；用密码登录时）。
#                        密码只经 sshpass -e 从环境变量读，不出现在命令行、文件和日志里。
#   DEPLOY_KNOWN_HOSTS   known_hosts 文件（默认 /workspace/.deploy/known_hosts；第一次连接自动记录指纹）
# 服务器上的名字（和 server/lib.sh 一致，可改）：APP_NAME（默认 xiuxian-dev2）、APP_PORT（默认 8090）、DB_NAME、DB_USER
# shellcheck disable=SC2034

: "${DEPLOY_HOST:?需要 DEPLOY_HOST（服务器地址）}"
DEPLOY_USER="${DEPLOY_USER:-root}"
DEPLOY_PORT="${DEPLOY_PORT:-22}"
DEPLOY_KNOWN_HOSTS="${DEPLOY_KNOWN_HOSTS:-/workspace/.deploy/known_hosts}"
DEPLOY_PASSWORD_ENV="${DEPLOY_PASSWORD_ENV:-SERVER_SSH_PASSWORD}"
APP_NAME="${APP_NAME:-xiuxian-dev2}"
APP_PORT="${APP_PORT:-8090}"
DB_NAME="${DB_NAME:-xiuxian_dev2}"
DB_USER="${DB_USER:-xiuxian_dev2}"
DEPLOY_PUBLIC_URL="${DEPLOY_PUBLIC_URL:-http://$DEPLOY_HOST:$APP_PORT}"
DEPLOY_PUBLIC_URL="${DEPLOY_PUBLIC_URL%/}"
# 本机保存后台管理员账号密码的文件（0600，KEY=VALUE；只按路径传给脚本，内容不进任何输出）
ADMIN_CRED_LOCAL="${ADMIN_CRED_LOCAL:-/workspace/.deploy/admin-credentials.env}"

say() { printf '\033[1;36m[部署]\033[0m %s\n' "$*"; }
oops() { printf '\033[1;31m[出错]\033[0m %s\n' "$*" >&2; exit 1; }

mkdir -p "$(dirname "$DEPLOY_KNOWN_HOSTS")"
_CTL="${TMPDIR:-/tmp}/xxdeploy-$(id -u)-%C"
SSH_OPTS=(-p "$DEPLOY_PORT" -o "UserKnownHostsFile=$DEPLOY_KNOWN_HOSTS" -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=20 -o ServerAliveInterval=20 -o ControlMaster=auto -o "ControlPath=$_CTL" -o ControlPersist=300)
SSH_PREFIX=()
if [ -n "${DEPLOY_SSH_KEY:-}" ]; then
  [ -f "$DEPLOY_SSH_KEY" ] || oops "私钥不存在：$DEPLOY_SSH_KEY"
  SSH_OPTS+=(-i "$DEPLOY_SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes)
elif [ -n "${!DEPLOY_PASSWORD_ENV:-}" ]; then
  command -v sshpass >/dev/null || oops "用密码登录需要 sshpass（apt install sshpass）。"
  # sshpass -e 从环境变量 SSHPASS 读密码；只导出给 ssh 子进程
  export SSHPASS="${!DEPLOY_PASSWORD_ENV}"
  SSH_PREFIX=(sshpass -e)
  # shellcheck disable=SC2054
  SSH_OPTS+=(-o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive)
else
  oops "没有登录方式：设 DEPLOY_SSH_KEY（私钥路径），或把密码放进环境变量 $DEPLOY_PASSWORD_ENV。"
fi
TARGET="$DEPLOY_USER@$DEPLOY_HOST"
SUDO=""
[ "$DEPLOY_USER" = "root" ] || SUDO="sudo -n"
# 传给服务器脚本的名字（都不是秘密）
REMOTE_ENV="APP_NAME=$APP_NAME APP_PORT=$APP_PORT DB_NAME=$DB_NAME DB_USER=$DB_USER"

rssh() { "${SSH_PREFIX[@]}" ssh "${SSH_OPTS[@]}" "$TARGET" "$@"; }
# 以 root 运行一条远程命令（参数是已经拼好的命令字符串）
rroot() { rssh "$SUDO env $REMOTE_ENV bash -c $(printf '%q' "$1")"; }
rsync_up() { # rsync_up 本地路径 远程路径 [其它 rsync 参数…]；压缩传输，只传变化的部分
  local src="$1" dst="$2"; shift 2
  rsync -az --no-owner --no-group --delete --partial "$@" -e "${SSH_PREFIX[*]} ssh ${SSH_OPTS[*]}" "$src" "$TARGET:$dst"
}
# upload_big 本地文件 远程目录：大文件切成几块、用几条独立的 SSH 连接同时传（单条连接到服务器只有几十 KB/s），
# 已传完的块下次不再传；在服务器上拼回原文件并核对 sha256。
upload_big() {
  local file="$1" dst="$2" name parts sum n="${UPLOAD_STREAMS:-8}" pids=() p rc=0
  name="$(basename "$file")"
  sum="$(sha256sum "$file" | cut -d' ' -f1)"
  parts="${DEPLOY_CACHE:-/workspace/.deploy/cache}/parts-$sum"
  if [ ! -f "$parts/.done" ]; then
    rm -rf "$parts" && mkdir -p "$parts"
    split -n "$n" -d -a 2 "$file" "$parts/part." && touch "$parts/.done"
  fi
  rssh "mkdir -p $dst/.parts-$sum"
  _send_parts() { # _send_parts 块文件...（并行传，返回是否全部传完）
  local p pids=() rc=0
  for p in "$@"; do
    ( # 每块最多重试 ${UPLOAD_RETRIES:-20} 次；断线后接着已传的部分继续
      for _ in $(seq "${UPLOAD_RETRIES:-20}"); do
        rsync -az --no-owner --no-group --partial --timeout=120 \
          -e "${SSH_PREFIX[*]} ssh ${SSH_OPTS[*]} -o ControlPath=none" "$p" "$TARGET:$dst/.parts-$sum/" && exit 0
        sleep 5
      done
      exit 1
    ) & pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p" || rc=1; done
  return "$rc"
  }
  _send_parts "$parts"/part.* || { echo "有分块没传完，重跑同一条命令会接着传。" >&2; return 1; }
  # 断线时服务器上残留的 rsync 接收端超时退出前会把它的半截文件写回原名，盖掉已经传完的块：
  # 等这些接收端都退出，再逐块核对 sha256，不一致的重传（最多 5 轮）。
  local round bad want got
  for round in 1 2 3 4 5; do
    rssh "for i in \$(seq 60); do pgrep -f '[r]sync --server.*$dst/.parts-$sum' >/dev/null || exit 0; sleep 5; done; exit 0"
    want="$(cd "$parts" && sha256sum part.* | sort -k2)"
    got="$(rssh "cd $dst/.parts-$sum && sha256sum part.* 2>/dev/null | sort -k2")"
    bad="$(join -1 2 -2 2 -a 1 <(echo "$want") <(echo "$got") | awk '$2 != $3 {print $1}')"
    [ -z "$bad" ] && break
    echo "第 $round 轮核对：$(echo "$bad" | wc -l) 块不一致，重传。" >&2
    # shellcheck disable=SC2046
    _send_parts $(for p in $bad; do echo "$parts/$p"; done) || { echo "有分块没传完，重跑同一条命令会接着传。" >&2; return 1; }
  done
  [ -z "$bad" ] || { echo "分块核对多轮仍不一致，重跑同一条命令。" >&2; return 1; }
  rssh "cd $dst && cat .parts-$sum/part.* > $name.tmp && echo '$sum  $name.tmp' | sha256sum -c --quiet && mv $name.tmp $name && rm -rf .parts-$sum"
}
rsync_down() { rsync -a -e "${SSH_PREFIX[*]} ssh ${SSH_OPTS[*]}" "$TARGET:$1" "$2"; }
remote_tmpdir() { rssh 'mktemp -d /var/tmp/xiuxian-up.XXXXXX'; }
close_ssh() { "${SSH_PREFIX[@]}" ssh "${SSH_OPTS[@]}" -O exit "$TARGET" 2>/dev/null || true; }
