# 本地模拟线上服务器 101.132.74.32（2026-10-19 只读勘察的结果）：
# Ubuntu 24.04 + systemd + sshd，已装 Postgres 16（库 xiuxian / 角色 xiuxian）和 Node 22.15.1（/usr/local/bin/node），
# 另有一个“别人的服务”占着 0.0.0.0:8080（xiuxian-api.service），用来检查部署脚本不会碰它。没有 nginx。
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends systemd systemd-sysv openssh-server sudo curl ca-certificates \
      iproute2 rsync xz-utils openssl cron postgresql-16 postgresql-client-16 python3 >/dev/null \
 && rm -f /etc/ssh/ssh_host_* && mkdir -p /root/.ssh && chmod 700 /root/.ssh \
 && (cd /lib/systemd/system/sysinit.target.wants/ && ls | grep -v systemd-tmpfiles-setup | xargs rm -f)
COPY node-v22.15.1-linux-x64.tar.xz /tmp/
RUN tar -C /usr/local --strip-components=1 -xJf /tmp/node-v22.15.1-linux-x64.tar.xz && rm /tmp/*.tar.xz
COPY regen-hostkeys.service xiuxian-api.service /etc/systemd/system/
RUN systemctl enable regen-hostkeys.service ssh postgresql cron xiuxian-api.service \
 && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/; s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
