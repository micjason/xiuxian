#!/usr/bin/env bash
# 启动本地模拟服务器（docker，需要 sudo）。SSH 在 127.0.0.1:2222（root，密码来自环境变量 SIM_ROOT_PASSWORD），
# 应用端口 8090 映射到 127.0.0.1:18090。用法：SIM_ROOT_PASSWORD=… tools/deploy/sim/run_sim.sh [--fresh]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
: "${SIM_ROOT_PASSWORD:?需要 SIM_ROOT_PASSWORD}"
[ -f "$HERE/node-v22.15.1-linux-x64.tar.xz" ] || cp /workspace/.deploy/cache/node-v22.15.1-linux-x64.tar.xz "$HERE/"
sudo docker build -q -t xiuxian-simserver "$HERE" >/dev/null
if [ "${1:-}" = "--fresh" ] || ! sudo docker inspect xxsim >/dev/null 2>&1; then
  sudo docker rm -f xxsim >/dev/null 2>&1 || true
  sudo docker run -d --name xxsim --hostname sim-101 --privileged --cgroupns=private \
    -p 127.0.0.1:2222:22 -p 127.0.0.1:18090:8090 --tmpfs /run --tmpfs /run/lock xiuxian-simserver >/dev/null
fi
for _ in $(seq 1 30); do sudo docker exec xxsim systemctl is-active -q ssh postgresql && break; sleep 1; done
# 模拟“已有的库和角色”
sudo docker exec xxsim bash -c "runuser -u postgres -- psql -Xqc \"select 1 from pg_roles where rolname='xiuxian'\" | grep -q 1 || runuser -u postgres -- psql -Xq -c 'create role xiuxian login' -c 'create database xiuxian owner xiuxian'" >/dev/null 2>&1 || true
printf 'root:%s\n' "$SIM_ROOT_PASSWORD" | sudo docker exec -i xxsim chpasswd
echo "模拟服务器就绪：ssh root@127.0.0.1 -p 2222"
