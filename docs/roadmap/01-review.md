# 01 现状诊断

评审基线：`dev` 分支 `b708380`，客户端 `game/project.godot` 版本 `0.6.7`，后端约 3000 行 TypeScript，后台约 1000 行 Vue，客户端约 1.2 万行 GDScript。`backend` 与 `admin` 的类型检查（`tsc --noEmit`、`vue-tsc --noEmit`）当前均通过。

严重程度：

- **S1 致命**：会丢数据、被盗号、或者让后台配置根本不生效。必须最先修。
- **S2 严重**：上线前必须修，否则多人使用时会出问题。
- **S3 改进**：影响开发效率或可维护性，按计划逐步改。

---

## 一、做得好的地方（保留）

1. **服务器权威的方向正确。** ADR-0006 已经确定修为、境界、战力、突破、掉落由服务器计算，客户端只展示。这是网游的行业标准做法，必须坚持。
2. **草稿/发布模型正确。** 后台改草稿、点发布生成不可变版本、玩家只读已发布版本。这和商业游戏的“配置表发布”流程一致。
3. **操作记录（审计日志）与具名修复程序。** 先预览、确认后写入、同一玩家只生效一次，思路很专业。
4. **密码与会话处理基本正确。** 密码用 argon2id，会话表只存令牌哈希，玩家会话与管理员会话分开。
5. **纯规则与接口分离。** `progress-rules.ts`、`power.ts`、`publish-rules.ts`、`drops.ts` 是不依赖数据库的纯函数并有单测，方向对。
6. **客户端已有完整的战斗/装备/功法规则原型。** `game/scripts/adventure/combat_rules.gd` 的“击杀用时 vs 阵亡用时”公式、五部位装备、四类功法，可以直接作为服务器实现的参考答案。
7. **Android 热更新链路做通了。** 签名校验、PackageInstaller 覆盖安装都已验证。

---

## 二、S1 致命问题

### S1-1 关键写操作没有放进数据库事务，并发会重复结算

- 位置：`backend/src/modules/player/service.ts`（`openProgress`、`tryBreakthrough`）、`backend/src/modules/content/service.ts`（`publish`）、`backend/src/modules/auth/service.ts`（`registerPlayer`）、`backend/src/modules/repairs/service.ts`（`applyRepair`）。
- 现象：设计文档和 `.cursor/rules/backend-authority.mdc` 都要求“锁住进度行，在同一事务里写进度和记录”。但代码里直接用 `deps.db` 执行，全仓库只有测试辅助 `test/db.ts` 用了 `db.transaction`。`SELECT ... FOR UPDATE` 在事务外执行时，语句一结束锁就释放，等于没锁。
- 后果：
  - 两个 `/me` 请求同时到达（手机每 5 秒轮询一次，切网重试时很常见），两边读到同一个 `lastSettledAt`，同一段时间的修为被加两次。
  - 突破时并发点击，可能扣两次修为或跳两级。
  - 发布中途出错，会留下两份 `published` 版本，或一份只复制了一半数据的版本。
  - 注册时插入了 `players` 但 `player_states` 失败，这个账号以后每次登录都报 500（`player missing`）。
- 为什么测试没发现：测试辅助函数把整个测试包在一个事务里，所以测试中“看起来”是原子的。

### S1-2 后台改的内容，大部分到不了手机

- 位置：`backend/src/modules/content/pack.ts` 的 `buildPublishedContent`、`saveDrop`、`stageRecords`；客户端 `game/scripts/adventure/adventure_config.gd`、`game/scripts/core/config_service.gd`。
- 现象：
  - 后台“物品”“技能”页面写的是关系表 `items`、`skills`。但发给手机的 `/content/published` 里，`adventure` 是当初导入的整份 JSON 原样返回，只把境界的攻防血合并进去了。**后台新增的物品、技能，或改过的物品数值，手机都看不到。**
  - 后台关卡页把掉落写在 `stages[].drops[{item_slug, chance(0–100 整数), quantity}]`；手机读的是 `stages[].monsters[].drops[{item_id, chance(0–1 小数), count}]`。**后台配的掉落手机完全不读。**
  - 掉落概率用 0–100 的整数，表达不了 0.5%、0.05% 这种 Boss 稀有掉落。行业通用是万分比（0–10000）。
- 本质原因：内容同时存在“关系表”和“整块 JSON 文档”两套格式，且服务器和手机各自理解一套。

### S1-3 全部走明文 HTTP，IP 地址写死在代码里

- 位置：`game/scripts/ui/player_api.gd`、`game/scripts/core/published_config.gd`（`HOST := "101.132.74.32"`，`PORT := 80`）、`admin/vite.config.ts`、`backend/src/modules/releases/service.ts`（`PUBLIC_BASE`）。
- 后果：用户名、密码、会话令牌在网络上明文传输，同一 Wi-Fi 下可被截获；换服务器必须重新发版；没有域名也就没法上 HTTPS。

### S1-4 开发环境直接连生产服务器

- 位置：`admin/vite.config.ts` 把 `/admin`、`/auth` 代理到 `http://101.132.74.32`；`backend/README.md` 写明“页面开发时不用在本机启动后端”。
- 后果：开发调试时点一下“发布”就直接改了线上玩家正在用的配置；测试账号、测试数据和真实玩家混在同一个库里。没有“开发 / 测试 / 生产”三套环境。

---

## 三、S2 严重问题

### 后端

| 编号 | 问题 | 位置 | 后果 |
|---|---|---|---|
| S2-1 | `/me` 每次调用都做一次“结算+写库+写操作记录”，而手机每 5 秒调一次 | `game/scripts/ui/main_screen.gd` 的 `_tick`（5 秒）→ `player/service.ts` `openProgress` | 每个在线玩家每天约 1.7 万行操作记录、1.7 万次行锁更新。100 人在线就是每天 170 万行日志，数据库很快变慢 |
| S2-2 | 注册没有任何校验 | `auth/routes.ts`、`auth/service.ts` | 用户名可为空格、超长、含特殊字符；密码 1 位也行；用户名重复直接抛数据库异常返回 500 |
| S2-3 | 登录失败分别返回 `unknown`、`bad_password` | `auth/service.ts` | 攻击者可以枚举哪些用户名已注册 |
| S2-4 | 没有频率限制 | 全部接口 | 登录可被暴力破解，注册可被刷号 |
| S2-5 | 没有服务端退出登录 | 客户端 `_logout_account` 只删本地文件 | 令牌在服务器上仍有效 30 天，过期会话从不清理 |
| S2-6 | 请求参数没有校验（只做了 `as` 类型断言） | 所有 `routes.ts` | 传错类型或缺字段直接触发数据库错误返回 500；数值可以是负数或 NaN |
| S2-7 | 没有统一错误格式 | 各 `routes.ts` 各写各的 `{reason}` | 客户端无法可靠区分“修为不足”“网络失败”“会话过期” |
| S2-8 | 后台数据库没有迁移一致性 | `backend/drizzle/0002_content_links_and_notices.sql` 是手写的，`meta/` 里没有对应 `0002_snapshot.json` | 下次 `drizzle-kit generate` 会把 0002 的改动再生成一遍，迁移执行失败 |
| S2-9 | 鉴权代码复制了 4 份 | `player/routes.ts`、`content/routes.ts`、`releases/routes.ts` 等各自的 `requireAdmin` | 改一处忘一处，容易留下没鉴权的接口 |
| S2-10 | 列表接口没有分页，且有 N+1 查询 | `player/service.ts` `listPlayers`、`operations/record.ts` `listOperations` | 玩家多了以后后台打不开 |
| S2-11 | 突破失败原因写错 | `tryBreakthrough` 在没有已发布配置时返回 `not_enough` | 排查问题时被误导 |
| S2-12 | 没有日志框架、健康检查、优雅停机 | `server.ts`、`app.ts`（`Fastify()` 未开 logger） | 线上出错无从排查；重启时正在处理的请求直接中断 |
| S2-13 | 版本发布把 APK 整个读进内存，由业务服务器直接下发 | `releases/routes.ts`、`releases/service.ts` | 小带宽云服务器上，几个人同时下载 APK 就会拖慢全部游戏接口 |

### 客户端

| 编号 | 问题 | 位置 | 后果 |
|---|---|---|---|
| S2-14 | 网络请求在主线程同步阻塞 | `player_api.gd`、`published_config.gd` 用 `while + OS.delay_msec` 轮询，最长卡 8 秒 | 网络慢时画面完全冻住；Android 上超过 5 秒无响应会弹出“应用无响应”（ANR） |
| S2-15 | 突破成功提示传错参数 | `main_screen.gd` `_on_breakthrough_pressed` 把 `realmSlug`（如 `qi_early`）当成新境界名、把旧境界速率当成新速率传给提示 | 玩家看到“突破至 qi_early，效率为旧值” |
| S2-16 | 本地单机玩法与账号模式并存 | `main_screen.gd` `_ready` 仍创建 `CultivationSession`、读写本地存档；没登录时突破走本地 | 两个真相源；开发者和 AI 都分不清哪个才是进度 |
| S2-17 | `main_screen.gd` 1698 行，承担了所有页面 | `game/scripts/ui/main_screen.gd` | 改任何一个页面都要读懂整个文件；AI 修改时极易误伤其他页面 |
| S2-18 | 每 5 秒拉一次服务器才更新数字 | `_tick.wait_time = 5.0` | 修为数字每 5 秒跳一下，体验差且浪费服务器。行业做法是：服务器给出“当前值+速率+服务器时间”，客户端本地插值显示 |

### 产品与规则文档

| 编号 | 问题 | 位置 |
|---|---|---|
| S2-19 | 需求冲突：ADR-0005 写“突破继续确定成功，不增加随机失败”，与负责人“突破有概率，战力越高越容易成功”的需求相反 | `docs/decisions/0005-long-term-gameplay-architecture.md` |
| S2-20 | 规则与现状矛盾：`content-admin.mdc` 规定后台“不可以发公告、改弹窗”，但后台已经有公告、弹窗、版本更新页面 | `.cursor/rules/content-admin.mdc`、`admin/src/layouts/AdminLayout.vue` |
| S2-21 | 文档过期：README、ADR-0006、`mvp-scope.md` 都写“后端和后台尚未实现”，实际已部署到云服务器 | `README.md`、`docs/decisions/0006-online-product.md`、`docs/product/mvp-scope.md` |

---

## 四、S3 结构与效率问题

1. **内容模型太绕。** 每次发布把境界/物品/技能整表复制一份（`realms`、`items`、`skills` 都带 `release_id`），关卡和洞府却是 JSON 文档。判断“已发布过的编号不能删”时要遍历历史所有版本逐个查询。行业做法是：草稿用普通表编辑，发布时把整份内容序列化成一个不可变的快照（JSON），带版本号和校验和。
2. **修为用 `double precision` 存。** 放置游戏数值增长快，浮点数长期累加有精度误差。修为、物品数量应该用整数（`bigint`），按“每 N 秒得 M 点”的整数节拍结算。
3. **客户端的长线系统（洞府、门派、灵兽、远行、飞升）全在本地。** 这些代码在服务器版本里都不能直接用。第一版线上不要移植，先冻结隐藏，保留设计文档，以后按服务器权威重写。
4. **没有 CI。** 没有任何自动化流水线；后端测试依赖本机 PostgreSQL，没人跑就不知道坏没坏。
5. **提交粒度过大。** 最近一个提交 `b708380` 改了 89 个文件、6795 行，混合了后端、后台、客户端、文档。出问题无法回退单个功能，也无法审查。
6. **AI 规则文件过多且分散。** `.cursor/rules/` 10 个、`.cursor/skills/` 7 个、`docs/superpowers/` 一套，部分互相矛盾（见 S2-19、S2-20）。执行代理会在相互矛盾的约束之间摇摆。
7. **后台表单全部是手填文本。** “下一境界”“对应技能”“种类”“品质”“部位”都要手打编号，打错一个字母要到发布时才报错，而且报错不指出是哪一条。
8. **没有数值模拟工具。** 策划改了每秒修为和突破消耗以后，没法直接看到“新玩家多久到筑基”。
9. **代码里有 `admin.id === "unused"` 这类测试残留**（`content/service.ts`、`repairs/service.ts`）。

---

## 五、诊断总结

| 维度 | 现状 | 目标 |
|---|---|---|
| 真相源 | 手机本地一套 + 服务器一套 | 只有服务器 |
| 内容格式 | 关系表 + 整块 JSON，两端理解不同 | 草稿表 → 发布快照（一种格式，两端共用） |
| 写操作 | 无事务 | 每个动作一个事务，行锁 + 幂等键 |
| 传输 | 明文 HTTP、IP 写死 | 域名 + HTTPS，按环境配置地址 |
| 环境 | 开发直连生产 | 本机开发 / 测试服 / 正式服三套 |
| 客户端结构 | 1698 行单文件，同步阻塞网络 | 页面拆分、异步网络、统一状态仓库 |
| 后台 | 通用表格手填编号 | 每类内容专用表单、下拉选择、校验、预览、版本回滚、数值模拟 |
| 质量 | 无 CI，大提交 | CI 必过、一任务一分支一合并 |
