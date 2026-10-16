# 在 Mac 上本地运行（后端 + 后台 + Godot 游戏）

适用：Mac 上已经装了 Docker，想在本机跑完整的一套：后端（带 PostgreSQL）、后台管理网页、Godot 编辑器里直接运行游戏。不需要手机，不需要云服务器。

分支：`dev2`（基于 `dev`）。全程只连本机 `127.0.0.1`，不会访问任何外部服务器。

> 说明：本清单在 Linux 盒子上按步骤跑通过（见文末「验证情况」）。没有在 Mac 上、没有用 Godot 图形编辑器、没有用 Docker 实际跑过——这几处标了 ⚠️。如果某一步和这里写的不一样，把终端里的原文报错发给开发，不要自己改。

---

## 0. 先准备（只做一次）

| 要装的 | 要求 | 怎么检查，看到什么算对 |
|---|---|---|
| Docker Desktop（或 OrbStack / Colima） | 已打开，处于运行中 | 终端 `docker info`，不报错并打印一堆信息 |
| Node.js | **22**（20.19 以上也能跑，但后台依赖要求 22，会有警告） | `node -v` 显示 `v22.x.x` |
| Git | 随便 | `git --version` |
| Godot | **4.7.2 stable，标准版（不是 .NET 版）** | 见第 3 节 |

装 Node 22（任选一种）：`brew install node@22 && brew link --overwrite node@22`，或用 nvm：`nvm install 22 && nvm use 22`。

取代码：

```bash
git clone https://github.com/micjason/xiuxian.git
cd xiuxian
git checkout dev2
```

成功：`git branch` 显示 `* dev2`。后面的命令都在这个 `xiuxian` 目录（仓库根目录）下执行。

> ⚠️ 关于 Git LFS：仓库的 `.gitattributes` 把图片、字体等标成了 LFS，但这些文件实际是当普通文件提交的（没有用 LFS）。如果你的 Mac 装过 git-lfs，克隆后 `git status` 可能显示很多图片「已修改」——这是误报，**不要提交**，忽略即可；想去掉提示可以在仓库里执行 `git lfs uninstall --local`。没装 git-lfs 的话完全不受影响。（这一点没有在装了 git-lfs 的机器上验证。）

---

## 1. 启动后端（含数据库）

### 1.1 一条命令：起数据库 + 建库 + 迁移 + 灌入原型数据 + 建后台管理员

```bash
tools/local/setup_local.sh
```

它会依次做：`docker compose up -d` 起 Postgres 16 → 生成 `backend/.env` → `npm ci` → 建库 `xiuxian_dev` 和 `xiuxian_test` → 数据库迁移 → 灌入原型 v1.2 内容并发布第 1 版 → 创建后台管理员。大约 1～3 分钟（第一次要下载 Postgres 镜像和 npm 包）。

成功时最后几行是：

```
seeded prototype v1.2 and published version 1
管理员 owner：created
全部完成。下一步：
```

- 中间会打印一段 `severity: 'NOTICE' ... will be truncated` 的信息，是 Postgres 的提示，**不是错误**，忽略。
- 重复运行是安全的：库已有不会重建，已发布的内容不会被覆盖，管理员已有不会改。第二次运行会看到 `database xiuxian_dev exists`、`content already published (version 1), skip seed`、`管理员 owner：exists`。
- 默认管理员：用户名 `owner`，密码 `xiuxian-local-1`（只用于本机）。想自己定：`ADMIN_USERNAME=我的名字 ADMIN_PASSWORD='至少8位的密码' tools/local/setup_local.sh`（密码至少 8 位、不能和用户名相同）。

**如果你已经有自己的 Postgres 容器**（占着 5432 端口）：不用 compose 起的那个，而是用你自己的。

1. 保证里面有一个能建库的账号（已有 `xiuxian`/`xiuxian` 的就不用做）。容器名先用 `docker ps` 查，然后：
   ```bash
   docker exec -it <你的容器名> psql -U postgres -c "create role xiuxian login password 'xiuxian' createdb;"
   ```
2. 先 `cp backend/.env.example backend/.env`，把 `backend/.env` 里的 `DATABASE_URL` 改成你的库（格式 `postgres://用户:密码@127.0.0.1:端口/xiuxian_dev`）。
3. 运行：`SKIP_DOCKER=1 tools/local/setup_local.sh`（不碰 Docker，库不存在会自动建）。

### 1.2 起后端

打开一个**新的终端窗口**（这个窗口要一直开着）：

```bash
cd backend
npm run dev
```

成功：打印一行 `... "msg":"Server listening at http://127.0.0.1:8080"`。后端地址就是 **http://127.0.0.1:8080**（端口来自 `backend/.env` 的 `PORT`，默认 8080；`HOST=127.0.0.1` 表示只有本机能访问）。

另开一个终端验证：

```bash
curl http://127.0.0.1:8080/healthz
```

成功：`{"ok":true,"version":"dev","contentVersion":1}`。`contentVersion` 是 1 说明原型内容已发布；是 `null` 说明没灌数据，回到 1.1 再跑一次。

停止后端：在那个窗口按 `Ctrl+C`。数据库在 Docker 里，不影响。以后每次想玩，只需要：打开 Docker → `cd backend && npm run dev`。

### 1.3 （可选）自己跑后端测试

```bash
cd backend
npm test
```

成功：最后显示 `Test Files 69 passed`、`Tests 260 passed`（约 1 分钟）。测试用的是 `xiuxian_test` 库，不会动你的开发库。

---

## 2. 后台管理系统（网页）

后端要先开着（第 1.2 步）。再开一个**新终端**：

```bash
cd admin
npm ci
npm run dev
```

成功：最后显示类似

```
VITE v7.x  ready in ... ms
➜  Local:   http://127.0.0.1:5173/
```

**用终端里 `Local:` 那一行的地址**打开浏览器（正常是 5173；如果 5173 被别的程序占了，Vite 会自动换成 5174 等，以终端显示为准）。

登录：用户名 `owner`，密码 `xiuxian-local-1`（或你在 1.1 里自己定的）。成功：进入后台首页（左侧菜单有 概览 / 玩家运营 / 游戏配置 / 发布中心 / 公告弹窗 / 系统）。

**再建一个管理员 / 改管理员密码**（在 `backend` 目录）：

```bash
cd backend
ADMIN_USERNAME=newadmin ADMIN_PASSWORD='至少8位的密码' npm run admin:ensure
```

成功：最后一行打印 `created`（新建）或 `exists`（已存在，没改动）。要重置某个已有管理员的密码：命令前加 `ADMIN_RESET=1`，最后一行打印 `reset`。

后台改了配置后，要在「发布」页发布，游戏里才会生效。

后台默认把请求转到 `http://127.0.0.1:8080`；后端换了端口的话：`VITE_API_PROXY=http://127.0.0.1:新端口 npm run dev`。

---

## 3. Godot 编辑器里直接运行游戏（不用手机）

### 3.1 装 Godot 4.7.2

1. 打开 https://godotengine.org/download/archive/4.7.2-stable/ ，在 **macOS**（Standard，Universal，不是 .NET）那一栏下载，得到 `Godot.app`（压缩包解压）。
2. 拖进「应用程序」。第一次打开如果提示“无法验证开发者”：右键 → 打开 → 打开。
3. 版本必须是 **4.7.2**（工程 `game/project.godot` 里写着 `config/features=…"4.7"…`，CI 和打包脚本都用 4.7.2）。不要用 `brew install godot` 直接装最新版，可能不是 4.7.2。
4. 检查：打开 Godot，窗口标题或「帮助 → 关于」显示 `4.7.2.stable`。

### 3.2 打开工程

1. 启动 Godot，在项目管理器点「导入」（Import）。
2. 选择文件 `xiuxian/game/project.godot`（注意是 `game` 目录里的，不是仓库根目录）→ 打开 → 「导入并编辑」。
3. **第一次打开会花十几秒到一两分钟**导入图片等资源（右下角有进度）。成功：编辑器打开，左下「文件系统」里能看到 `scenes`、`scripts`、`assets` 等。
4. 如果进度条停在某个字体文件（如 `NotoSansSC-Regular.subset.woff2`）超过 2 分钟不动：这是 Godot 导入字体时偶发的卡住（在 Linux 无头模式下遇到过，卡住后关掉重开即可，已导入的会保留）。关闭 Godot，重新打开工程继续导入。
5. 如果弹出“有插件/脚本错误”：先关掉编辑器再重新打开一次（第一次导入时偶尔会因为资源还没导完而报错），再不行见文末「排错」。

### 3.3 运行游戏

1. 确认后端在跑（第 1.2 步，`curl http://127.0.0.1:8080/healthz` 有返回）。
2. 编辑器右上角点 ▶（运行项目），或按 `⌘B`（F5 在 Mac 上常被系统占用，以右上角按钮为准）。主场景已经设好，不用选。
3. 成功：弹出一个竖屏小窗口（540×960，项目设置里的窗口缩放），先看到登录页：游戏标题、「用户名」「密码」输入框、「服务器地址」输入框、「登录」「注册」两个按钮。

### 3.4 服务器地址

- 登录页的「服务器地址」默认已经是 **`http://127.0.0.1:8080`**（来自工程设置 `xiuxian/network/api_base_url`），本机运行**不用改**。
- 后端不在 8080（改了 `PORT`）时，直接在这个输入框里改成 `http://127.0.0.1:新端口`，点登录或注册时会保存。
- 安卓模拟器用的 `10.0.2.2` 之类地址和这里无关，不用管。
- 已保存的地址在 `~/Library/Application Support/xiuxian/server_url.txt`（Godot 用户目录，工程名 `xiuxian`）。填错想恢复默认：删掉这个文件再运行。⚠️ Mac 上的这个路径是按 Godot 的规则推断的（Linux 上实测在 `~/.local/share/xiuxian/`），没有在 Mac 上看过。

### 3.5 第一次注册 / 登录

1. 在登录页填**用户名**（2～16 位，中文/字母/数字/下划线）和**密码**（随便，不能空；本机测试用，别用你平时的密码）。
2. 点「**注册**」。成功：登录页消失，进入主界面：顶部是境界 `炼气一层` 和战力，底部四个页签 修炼 / 背包 / 功法 / 洞府，修为数字开始增长。
3. 失败的话登录页下方会出红字：
   - `网络失败，请稍后再试`：连不上后端——后端没开或地址不对，见「排错」。
   - `注册失败，换一个用户名试试`：用户名已被注册——改点「登录」，或换一个名字。
   - `服务器地址不对`：地址格式要 `http://主机:端口`。
4. 以后再运行：登录会自动保存凭证（`player_token.txt`），一般直接进游戏；被退回登录页就点「登录」。
5. 想换一个新账号 / 重置玩家：删除 `~/Library/Application Support/xiuxian/player_token.txt`，再用新用户名注册。

### 3.6 （可选）命令行检查

在仓库根目录。把 `GODOT` 换成你的 Godot 可执行文件（Mac 上通常是 `/Applications/Godot.app/Contents/MacOS/Godot`）：

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
$GODOT --headless --path game --import                # 导入资源，退出码 0
$GODOT --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```

成功：GUT 结尾 `Tests 173`、`Passing Tests 172`、`Failing Tests 1`。**那 1 个失败是已知的老问题**（`test_main_screen_loop` 在无头模式下字体加载报错，与后端和联网无关），不影响运行。

---

## 4. 排错

| 现象 | 原因 / 怎么办 |
|---|---|
| `tools/local/setup_local.sh`：`Docker 没有运行` | 打开 Docker Desktop，等菜单栏图标显示运行中，再重跑脚本。 |
| `port is already allocated` / `address already in use`（5432） | 本机另有 Postgres 占着 5432（比如你自己的容器）。要么 `docker stop` 掉它再 `cd backend && docker compose up -d`；要么用 1.1 里「已经有自己的 Postgres」的做法（`SKIP_DOCKER=1`）。 |
| 脚本反复 `数据库还没好，2 秒后重试` 后失败 / 后端 `ECONNREFUSED 127.0.0.1:5432` | Postgres 没起来或地址不对。`docker ps` 看容器在不在；`docker compose logs postgres`（在 `backend/` 目录）看日志；核对 `backend/.env` 的 `DATABASE_URL`。 |
| `password authentication failed` | `DATABASE_URL` 里的用户名/密码和数据库不一致。compose 起的库账号是 `xiuxian`/`xiuxian`。如果以前用别的密码起过 compose，旧数据卷还在：`cd backend && docker compose down -v` 会**删掉库里所有数据**，然后重跑脚本。 |
| 后端 `EADDRINUSE :::8080` / `127.0.0.1:8080` | 8080 被占用。`lsof -i :8080` 看是谁；关掉它，或在 `backend/.env` 改 `PORT`，并在 Godot 登录页改地址、后台用 `VITE_API_PROXY`。 |
| 后端启动立刻退出，提示 `缺少或无效的环境变量: …` | `backend/.env` 缺项。删掉它重新 `cp backend/.env.example backend/.env`。 |
| `node: bad option: --env-file-if-exists` | Node 太旧（需要 20.19 以上）。装 Node 22。 |
| `npm ci` 报 `EBADENGINE` 警告 | Node 不是 22，只是警告，能跑；建议升到 22。 |
| 后台页面空白 / 登录一直转圈 / 弹“网络错误” | 后端没开，或后台用的不是终端 `Local:` 打印的那个地址。后端开着，再刷新。 |
| 后台提示账号或密码不正确 | 用户名密码按 1.1 里设的；忘了就用 `ADMIN_RESET=1 ADMIN_USERNAME=… ADMIN_PASSWORD=… npm run admin:ensure`（在 `backend/` 目录）重置。 |
| 游戏登录页红字「网络失败，请稍后再试」 | 后端没开 / 地址不对。先 `curl http://127.0.0.1:8080/healthz`，再核对登录页「服务器地址」；曾保存过别的地址就删 `server_url.txt`（见 3.4）。 |
| Godot 打开工程报资源缺失 / 脚本解析错误 / 满屏红字 | 一般是第一次导入没完成。关闭编辑器 → 删除 `game/.godot` 文件夹（只是缓存，会重新生成）→ 重新打开工程等导入完。仍有错：确认版本是 4.7.2 标准版，不是 4.6 / 4.8 / .NET 版。 |
| 第一次导入卡住不动（字体文件） | 关掉 Godot 重新打开工程，会接着导入（盒子上无头导入偶发卡住，重试一次就过）。 |
| 运行后窗口很小 | 正常，项目设置里窗口是 540×960（逻辑分辨率 1080×1920 的一半）。可以拖拽放大。 |
| 控制台一堆 `FreeType: Error loading font` | 无头模式 / 部分环境下的字体提示，不影响登录和游戏。 |
| 想把一切重置成刚装好的样子 | `cd backend && docker compose down -v`（**删库**），再 `tools/local/setup_local.sh`；游戏侧再删 `~/Library/Application Support/xiuxian/` 里的 `player_token.txt`。 |

---

## 5. 验证情况（开发在 Linux 盒子上做的）

从 `proto/week1` 的全新克隆（等同 `dev2` 的内容）按本清单执行，实测通过的：

- ✅ 数据库建库、迁移、灌入原型内容并发布版本 1、创建管理员（一条命令，约 6 秒），重复运行幂等。
- ✅ 后端 `npm run typecheck`、`npm run lint`、`npm test`（69 个测试文件 / 260 个测试全过）。
- ✅ 后端 `npm run dev` 监听 `127.0.0.1:8080`，`/healthz` 返回 `contentVersion: 1`；注册、登录、后台管理员登录接口返回令牌。
- ✅ 后台 `npm ci`、`vue-tsc`、`eslint`、`npm run build` 通过，`npm run dev` 能起，通过它的代理能登录管理员。
- ✅ Godot 4.7.2：全新克隆首次 `--import` 通过（偶发卡在字体导入，重试一次通过，见第 3.2 步）；GUT 173 个测试 172 个通过（1 个已知老问题）；用无头真实后端联调脚本对本地后端注册、登录并读取玩家状态成功（炼气一层、战力 494）。

**没有验证（需要你在 Mac 上第一次跑时留意）：**

- ⚠️ 没有在 Mac 上跑；Mac 特有的路径（`~/Library/Application Support/xiuxian/`）、Godot 首次打开的系统提示、`brew` 命令是按常规写的。
- ⚠️ 没有用 Docker 实际跑：盒子上没有 Docker，改用同版本（Postgres 16）的本地数据库、通过 `SKIP_DOCKER=1` 路径验证；`docker compose up -d` 这一步本身未跑过（compose 文件是项目早就在用的）。
- ⚠️ 没有人在 Godot 图形编辑器里点过 ▶，没有亲眼看登录页和主界面；只验证了无头导入、单元测试和用真实后端的无头联调。
- ⚠️ 没有真机 / 模拟器验证（本次也不需要）。
- ⚠️ 没有装了 git-lfs 的机器上验证 `git status` 的表现。

---

## 附：拿到 bundle 文件后，怎么变成 `dev2` 分支并推送

bundle 文件 `xiuxian-proto-week1.bundle` 只包含 `dev` 之后的提交。在已经克隆了仓库的 Mac 终端里执行（先 `cd` 到仓库目录）：

```bash
git fetch origin dev                                   # 确保本地有 dev（838d557）
git fetch /path/to/xiuxian-proto-week1.bundle proto/week1:dev2   # 把 bundle 里的提交取成本地分支 dev2
git push origin dev2                                   # 普通推送，不要加 --force
```

成功后 GitHub 上会出现 `dev2`，最新提交应为 `f6206b4`；`dev` 和 `main` 不会被改动。用 `git log --oneline -1 dev2` 可以核对。如果第二步报缺少前置提交，说明本地的 `dev` 不是 838d557，先执行 `git checkout dev && git pull` 再重试。
