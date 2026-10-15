# 怎样让 Chengpeng 在自己的安卓手机上连后端玩（调研，没有对外暴露任何东西）

日期：2026-10-16（Asia/Shanghai）。只做了调研：没有启动任何隧道，没有开放任何端口，没有登录任何账号。下面"在这台盒子上实测了什么"一节写清楚哪些是测出来的，哪些是文档/经验判断。

## 0. 先说结论

**推荐：A 方案——在 Chengpeng 自己的电脑上起后端（docker compose 起 Postgres + 一个启动脚本），手机和电脑连同一个 Wi-Fi，在登录页「服务器地址」填 `http://电脑局域网IP:8080`。** 数据只在他自己的电脑上，不经过公网，不碰共用的盒子，APK 现在就允许明文 http，不用改包。

备选：
- **B（最省事但要装 adb）**：USB 线 + `adb reverse tcp:8080 tcp:8080`，登录页填 `http://127.0.0.1:8080`。不依赖 Wi-Fi/路由器设置，适合公司 Wi-Fi 或有"客户端隔离"的网络。
- **C（手机走 4G / 不在同一网络）**：在他自己的电脑上再起一个 cloudflared 快速隧道（`cloudflared tunnel --url http://localhost:8080`），得到 `https://随机名.trycloudflare.com`，登录页填它。不需要注册账号，但这是公网地址，见风险。
- **不推荐：从这台盒子开隧道**。盒子是所有 agent 共用的一台机器，里面有测试库、浏览器登录态；而且实测这台盒子的出口只放行 443，cloudflared 隧道需要的 7844 端口连不出去（见 §2）。

## 1. 选项对比

| 方案 | Chengpeng 要做什么 | 手机填什么 | 优点 | 缺点 / 风险 |
|---|---|---|---|---|
| A 局域网（推荐） | 电脑上装 Docker（或本机 Postgres）→ 运行启动脚本 → 手机同一 Wi-Fi | `http://192.168.x.x:8080`（电脑的局域网 IP） | 无公网暴露；数据在自己电脑；延迟低；无需账号 | 电脑得开着；路由器若开了"AP/客户端隔离"或访客网络连不通；电脑防火墙要放行 8080；换网络 IP 会变 |
| B USB adb reverse | 开手机"开发者选项 → USB 调试"，装 adb，插线 | `http://127.0.0.1:8080` | 不受 Wi-Fi 影响；不暴露到局域网 | 要插线、要装 adb；拔线就断 |
| C 他电脑上的 cloudflared 快速隧道 | 装 cloudflared，运行一条命令，把 `https://…trycloudflare.com` 填进手机 | `https://随机名.trycloudflare.com`（每次重开会变） | 手机在 4G 也能玩；自带有效的 https 证书；不需要账号 | 地址在公网上，谁拿到都能打到注册/登录接口和后台登录页；随机名不是密码；隧道断了地址就失效 |
| D 盒子上开隧道 | — | — | — | 不推荐，理由见 §2、§5 |
| E 租云服务器（仓库里已有 tools/deploy、nginx 配置） | 买机器、域名、证书 | `https://域名` | 最正规，随时能玩 | 成本和运维；项目规则里写了"开发过程中不要访问云服务器地址"，不属于这次的"最省事" |

## 2. 在这台盒子上实测了什么（只读、没有暴露东西）
- 盒子系统 x86_64，Node 20.19、npm 9，**没有** docker/podman、cloudflared、ngrok、ssh 客户端。
- 能下载并运行 cloudflared：从 GitHub releases 下载 `cloudflared-linux-amd64`，`--version` 输出 2026.10.1。**只执行了 `--version`，没有启动隧道。** 二进制放在 `/tmp/cfd/cloudflared`，没有进仓库。
- 出口 TCP 连通性（只做连接测试，不传数据）：
  - `api.trycloudflare.com:443` 通；`registry.npmjs.org`、`github.com` 通（HTTPS）。
  - `region1/2.v2.argotunnel.com:7844` **连不上**（cloudflared 隧道的固定端口）；域名解析到的是 `198.18.0.1`（像是出口代理的占位地址）。
  - `localhost.run:22`、`serveo.net:22`（SSH 隧道）**连不上**。
  - `connect.ngrok-agent.com:443` 通，但 ngrok 必须注册账号拿 authtoken，不符合"不登录任何人"。
  - `loca.lt:443` 通，但 localtunnel 的数据通道用的是服务端分配的高位端口，在这个出口策略下能不能通**没有测**（测通就得真的开隧道，等于对外暴露，所以没做）。
- 所以：**在这台盒子上，cloudflared 快速隧道大概率起不来**（7844 被挡）；这是根据端口测试的推断，没有真的启动验证。

## 3. 推荐方案的具体步骤（A，Chengpeng 的电脑）

前提：电脑装了 Node 20+ 和 Docker（Docker Desktop 或 OrbStack/Colima 都行）。仓库在本地分支 `proto/week1`。

一次性准备（约 5 分钟）：
1. `cd backend && docker compose up -d`（起 Postgres 16，库名 `xiuxian_dev`；compose 里端口只绑 127.0.0.1，不暴露局域网）。
2. `cp .env.example .env`，把里面的 `PUBLIC_BASE_URL` 和 `APK_BASE_URL` 改成 `http://<电脑局域网IP>:8080`（这两个只影响后台的 APK 链接，玩游戏本身不依赖，但改了更整齐）。
3. `npm install`
4. `npm run db:migrate`
5. 写入原型内容并发布：`npx tsx --env-file=.env src/scripts/seed-prototype.ts`（目前不在 package.json 的 scripts 里，直接这样跑；"一键脚本"里会包含它）。
6. 可选：`npm run admin:create -- --username owner --password '至少八位的密码'`（要用后台改配置才需要）。

每次玩：
1. `cd backend && npm run dev`（监听 0.0.0.0:8080；源码里 `app.listen({ host: "0.0.0.0" })` 已经是这样）。
2. 查电脑局域网 IP：macOS `ipconfig getifaddr en0`；Windows `ipconfig` 看 IPv4；Linux `hostname -I`。
3. 电脑防火墙放行 `node` 的入站连接（macOS 第一次会弹窗，点"允许"）。
4. 手机连同一个 Wi-Fi；先用手机浏览器打开 `http://<IP>:8080/healthz` 看通不通（后端有这个健康检查接口）。
5. 装 `xiuxian-debug-v9a.apk`（或之后的版本），打开游戏，**登录页最上面的「服务器地址」**填：`http://192.168.1.23:8080`（换成自己的 IP，**必须带端口 8080**，写 `http://` 也行不写会自动补；结尾的 `/` 会自动去掉；不要有空格）。再填用户名、密码，点"注册"，然后登录。地址会保存在手机里，下次不用再填；换了网络 IP 变了要重新改。
   - 如果想让手机里什么都不用填：构建时 `tools/android/build_debug_apk.sh --api-base http://192.168.1.23:8080`，把地址写进包里（但 IP 一变就要重新打包，不如手填灵活）。

可以做成"一键启动脚本"（建议放 `tools/play/start.sh`，这次没有写进仓库，只给出内容草稿，需要时再加）：
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../backend"
IP=$( (ipconfig getifaddr en0 2>/dev/null) || (hostname -I 2>/dev/null | awk '{print $1}') )
docker compose up -d
[ -f .env ] || cp .env.example .env
sed -i.bak "s|^PUBLIC_BASE_URL=.*|PUBLIC_BASE_URL=http://$IP:8080|;s|^APK_BASE_URL=.*|APK_BASE_URL=http://$IP:8080|" .env
npm install --no-audit --no-fund
npm run db:migrate
npx tsx --env-file=.env src/scripts/seed-prototype.ts   # 已有内容时重复运行的行为需先确认（见 §6）
echo "手机登录页「服务器地址」填：http://$IP:8080"
npm run dev
```

## 4. HTTPS 还是明文 http（Android 上的含义）
- 现在的 APK 在构建时给 `AndroidManifest` 加了 `usesCleartextTraffic="true"`（`build_debug_apk.sh`，已用 `aapt2` 检查过），所以 `http://局域网IP:8080` 可以直接连，不用证书。
- 游戏里的地址校验只认 `http://` 或 `https://`（`ServerAddress.normalize`），两种都行。
- 明文 http 的含义：同一 Wi-Fi 里的人理论上能看到用户名、密码和 token。这是开发/自家 Wi-Fi 的做法，可以接受，但**不要用公共 Wi-Fi，也不要用平时在别处用的密码**，测试账号用一次性密码。
- https：隧道（方案 C）自带有效证书，Godot 用系统信任的根证书验证，能正常连（**没有在真机上验证过**）。自己签发的证书手机默认不信任，会连不上，所以局域网方案别折腾 https。
- 正式发布的包不应该保留明文开关（`build_debug_apk.sh` 是调试包专用的补丁，正式包要走 https + 域名，见 `tools/deploy`）。
- 版本检查：带 `/me/…` 的接口会比较请求头 `x-client-version` 与内容里的 `minClientVersionCode`；v9a 的 versionCode 是 28 以上；是否会被拒取决于后台全局设置里的最低版本（没有设置就是 0，不会拒），第一次连不上时先看这一项。

## 5. 风险
**数据**
- A/B：玩家数据在他自己电脑的 Docker 卷里，删卷即清空。和盒子上的测试库互相独立。
- 密码用 argon2 存；但明文 http 下传输不加密（见 §4）。
- 种子脚本会往当前库写内容并发布；对已有数据的库重复执行的行为我没有核实，别对有重要数据的库跑（§6）。

**安全**
- 后端监听 `0.0.0.0`，同一局域网的任何设备都能访问接口和后台登录页：把后台管理员密码设成强密码，`ENABLE_GM_TOOLS` 保持 `false`（`.env.example` 默认就是 false；GM 工具是调试用的改数据入口）。
- 注册/登录有限流（登录约 5 次/分钟，注册约 10 次/分钟，按 IP）。通过隧道访问时，后端没有开 `trustProxy`，所有请求会被看成同一个来源 IP，限流是全局共用的——一个人玩没问题，被人刷会误伤自己。
- 方案 C 的公网地址：随机域名不是秘密；任何拿到链接的人可以注册账号、试后台登录。用完立刻关隧道（Ctrl+C），不要发给别人，不要长期开。
- Postgres 只绑 `127.0.0.1`（compose 里已这样写），不要改成 0.0.0.0，也不要把 5432 做端口转发。

**共用的盒子**
- 盒子是同一用户所有 agent 共用的一台机器：共用文件系统、共用的测试数据库（xiuxian_test/e2e/sim）、共用的浏览器登录态。在盒子上开公网隧道，等于把这台机器上的服务（以及它连着的库）放到公网；盒子重启或被别的任务占用端口，隧道随时会断。所以**不建议在盒子上给他玩**。
- 另外，盒子的出口只放行 443（实测），隧道本来就起不来（§2）。

## 6. 没验证 / 需要确认的
- 没有在真机或模拟器上跑过任何连接；A、B、C 的手机端连接都是按代码和 Android 的行为推断的。
- 没有真的启动 cloudflared、localtunnel 或任何隧道（要求不能对外暴露）；"盒子上起不来"是端口连通测试后的推断。
- 没有在一台干净的电脑上跑一遍 docker compose + 种子脚本；`seed-prototype.ts` 对已有数据库的重复执行是否安全、没有测。
- Chengpeng 的电脑系统、路由器是否开了客户端隔离，未知。
- 后台管理页（admin/）这次没有纳入：只玩游戏不需要起它；要用就再起 `admin/` 的 `npm run dev`，同样只开在局域网。
