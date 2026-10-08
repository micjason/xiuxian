# 03 分阶段开发任务

任务编号格式 `P<阶段>-<序号>`。必须按阶段顺序执行；同一阶段内按序号执行，除非任务写明“可并行”。每个任务完成的标准是：**验收标准全部满足 + 列出的测试全部通过 + 按 [04-execution-rules.md](04-execution-rules.md) 汇报**。

规格（字段、公式、接口）一律以 [02-target-architecture.md](02-target-architecture.md) 为准，本文只写“做什么、改哪里、怎么验收”。

## 总览

| 阶段 | 名称 | 目标 | 预估 |
|---|---|---|---|
| P0 | 基线整理 | 纠正文档、确定决策、建本机开发环境和 CI | 2 天 |
| P1 | 后端地基加固 | 事务、鉴权、校验、错误码、账号安全、日志、迁移重建 | 4 天 |
| P2 | 内容配置系统重做 | 新内容表、发布快照、种子导入、后台专用表单、版本历史、模拟工具 | 6 天 |
| P3 | 服务器核心循环 | 状态、属性战力、修为、概率突破、装备、功法、关卡 Boss、掉落、幂等 | 7 天 |
| P4 | 客户端改为纯展示 | 异步网络、状态仓库、页面拆分、修炼/历练/行囊/功法四页接服务器 | 8 天 |
| P5 | 挂机打怪与离线收益 | 挂机地点、灵石、离线报告 | 3 天 |
| P6 | 后台开发辅助 | 玩家详情、GM 工具、数据看板 | 3 天 |
| P7 | 上线准备 | HTTPS、部署脚本、备份、压测、监控、强制更新 | 4 天 |
| P8 | 长线玩法（以后） | 洞府、门派等按 ADR-0005 在服务器上重做 | 另行规划 |

完成 P3 + P4 后，“注册 → 凡人 → 挂机修为 → 概率突破 → 打 Boss → 掉装备和功法书 → 穿戴学习 → 战力提升 → 更容易突破”的完整循环即可在手机上玩通。

### 部署节奏（重要）

- P0、P1 完成后可以部署到现在的云服务器：它们只修安全和可靠性问题，接口行为对现有 `0.6.x` 客户端保持兼容（旧路径别名保留）。
- **P2 开始，内容和玩家表结构不兼容旧客户端。** P2–P4 期间新后端只部署到本机和测试服（`xiuxian_staging` 库）；正式服保持 P1 完成时的版本不动。
- P4 完成后，新后端、新后台、新客户端一起切换到正式服，旧客户端通过 426 强制更新。

---

## P0 基线整理

### P0-1 纠正过期文档

- 改：`README.md`、`docs/decisions/0006-online-product.md`、`docs/product/mvp-scope.md`、`backend/README.md`。
- 内容：删除“backend/admin 尚未实现”等过期描述；写明当前已部署状态、本机开发方式（见 P0-3）；在 README 的“目录职责”里加入 `docs/roadmap/`，并写明“后续开发以 `docs/roadmap/` 为准”。
- 验收：全仓库搜索“尚未实现”“尚未购买”不再出现与事实不符的句子。

### P0-2 新增 ADR-0007 并整理 AI 规则

- 新增 `docs/decisions/0007-server-authoritative-core-loop.md`，记录以下决定：
  1. 突破改为有概率，成功率受战力影响，带保底（取代 ADR-0005 中“突破确定成功”）。
  2. 客户端只展示，所有本地结算代码下线；旧手机本地存档不迁入账号。
  3. 内容模型改为“草稿表 + 不可变发布快照”，概率统一用万分比。
  4. 后台分“内容配置 / 发布 / 数值工具 / 玩家 / 运营 / 测试工具”六组；GM 工具只在测试环境开启。
  5. 洞府、门派、灵兽、远行、飞升暂停，第一版不上线。
- 在 ADR-0005 顶部状态行注明“突破规则已被 ADR-0007 取代”。
- 改 `.cursor/rules/content-admin.mdc`：与 ADR-0007 第 4 条一致，删除与现有公告/弹窗页面矛盾的句子。
- 改 `.cursor/rules/backend-authority.mdc`：补充“每个改变进度的接口必须在 `withTransaction` 内执行并锁行”“必须有并发测试”。
- 新增 `.cursor/rules/roadmap.mdc`（alwaysApply）：一句话“实现任何功能前先读 `docs/roadmap/02-target-architecture.md` 对应章节；本组文档与旧文档冲突时以本组为准”。
- 在 `docs/superpowers/plans/` 下两个旧计划文件顶部注明“已被 docs/roadmap 取代，不再执行”。
- 验收：规则文件之间、规则与 ADR 之间不再有互相矛盾的句子。

### P0-3 本机开发环境

- 改 `backend/docker-compose.yml`：Postgres 16，数据卷持久化，启动脚本创建 `xiuxian_dev` 和 `xiuxian_test` 两个库。
- 新增 `backend/.env.example`（变量见 02 §8.1），`backend/src/config.ts` 用 zod 读取并校验环境变量，缺失时打印缺哪个并退出。后端启动时自动加载 `backend/.env`（用 Node 22 的 `--env-file` 或 `dotenv`）。
- 改 `admin/vite.config.ts`：代理目标从环境变量 `VITE_API_PROXY` 读取，默认 `http://127.0.0.1:8080`。**删除指向 101.132.74.32 的默认值。**
- 改 `backend/package.json` 脚本：`dev`、`test`（使用 `xiuxian_test` 库）、`db:generate`、`db:migrate`、`db:seed`、`typecheck`、`lint`。
- 新增 `docs/operations/local-dev.md`：从零开始在 Mac 上跑起三端的步骤（装 Docker → 起库 → 迁移 → 导入种子 → 建管理员 → 起后端 → 起后台 → Godot 运行）。
- 验收：按 `local-dev.md` 在一台干净机器上能跑起后端和后台，后台能登录；开发过程中不会访问 101.132.74.32。

### P0-4 代码规范与 CI

- `backend/`、`admin/` 加 ESLint（typescript-eslint 推荐规则）+ Prettier，加 `npm run lint`、`npm run format`。
- 新增 `.github/workflows/ci.yml`，在 push 和 PR 时运行：
  - backend：`npm ci` → `typecheck` → `lint` → 用 Postgres service 跑 `db:migrate` + `test`；
  - admin：`npm ci` → `vue-tsc --noEmit` → `lint` → `vite build`；
  - game（可后做）：用 Godot 4.7.2 无头镜像运行 GUT。
- 新增 `.github/pull_request_template.md`：任务编号、改动、验证、风险四段。
- 验收：一个故意写错类型的分支 CI 失败；修好后 CI 通过。

---

## P1 后端地基加固

> 本阶段不新增玩法，只修现有代码，使后续功能建在可靠的地基上。

### P1-1 事务封装与并发结算修复

- 新增 `backend/src/db/tx.ts`：`withTransaction(db, fn)`，内部调用 `db.transaction`，并导出类型 `Tx`。约定：service 层所有会写数据的函数第一个参数是 `Tx`，由路由层用 `withTransaction` 包起来调用。
- 改 `player/service.ts`：`openProgress`、`tryBreakthrough` 在事务内执行，`lockedPlayer` 的 `FOR UPDATE` 生效；失败记录的写入放在事务外单独写（因为事务回滚会把失败记录一起回滚）。
- 改 `auth/service.ts`：`registerPlayer` 的插入账号、插入状态、发会话、写记录放在同一事务。
- 改 `content/service.ts` 的 `publish`、`repairs/service.ts` 的 `applyRepair`、`releases/service.ts` 的 `saveRelease`：放进事务。
- 修改测试辅助 `test/db.ts`：提供 `withCleanDb`，每个测试前清空所有表（`TRUNCATE ... CASCADE`），**不再把整个测试包在一个事务里**，这样才能测出真实的事务行为。
- 新增测试 `player/concurrency.test.ts`：同一玩家同时发起 10 个结算请求（`Promise.all`），最终修为等于只结算一次的结果；同时发起 5 次突破，境界只升一级。
- 验收：并发测试在修改前失败、修改后通过（先写测试，再改代码）。

### P1-2 统一鉴权插件与路由前缀

- 新增 `backend/src/plugins/auth.ts`：Fastify 插件，提供 `app.requirePlayer`、`app.requireAdmin(role?)` 两个 `preHandler`，把会话挂到 `request.actor`。删除各 `routes.ts` 里复制的 `requirePlayer` / `requireAdmin`。
- 所有路由改到 `/api/v1` 前缀下，旧路径注册为别名（同一个处理函数），并在响应头加 `Deprecation: true`。
- 新增测试：遍历应用的所有路由，凡是 `/api/v1/admin/` 开头的，用玩家令牌请求必须 403，不带令牌必须 401。
- 验收：`grep -r "requireAdmin(" backend/src/modules` 只出现在插件注册处。

### P1-3 请求校验、统一错误格式

- 引入 `zod` 和 `fastify-type-provider-zod`。每个路由定义 `body` / `params` / `querystring` schema。
- 新增 `backend/src/shared/errors.ts`：`AppError(code, httpStatus, message, details?)` 和错误码常量（见 02 §5.1）。
- 在 `app.ts` 注册全局 `setErrorHandler`：zod 错误 → 400 `INVALID_INPUT`；`AppError` → 对应状态码；其他错误 → 记日志并返回 500 `INTERNAL`，不泄露堆栈。
- 把现有 `{reason: ...}` 的返回全部改成统一格式；`PublishRejected` 改为 `AppError("PUBLISH_REJECTED", 400, ..., {errors})`。
- 修复 01-review S2-11：没有已发布内容时返回 503 `CONTENT_NOT_PUBLISHED`。
- 同步修改后台 `admin/src/api.ts` 读取 `error.message`。
- 验收：对每个接口发一个缺字段的请求，返回 400 且格式统一；没有任何接口因参数问题返回 500。

### P1-4 账号安全

- 用户名：去掉首尾空格后 2–16 位，只允许中文、字母、数字、下划线；大小写不敏感唯一（存 `username_lower` 唯一列或用 `citext`）。
- 密码：8–64 位，不能与用户名相同。
- 注册重复 → 409 `USERNAME_TAKEN`；登录失败统一 401 `INVALID_CREDENTIALS`（操作记录里仍分别记录 `unknown` / `bad_password`）。
- 新增 `POST /api/v1/auth/logout`、`POST /api/v1/admin/auth/logout`：设置 `revoked_at`。`readSession` 检查 `revoked_at`，并在距上次更新超过 1 小时时更新 `last_seen_at`。
- 引入 `@fastify/rate-limit`，限额见 02 §8.3。
- 新增定时清理：进程内每小时删除过期超过 7 天和已撤销超过 7 天的会话（用 `setInterval`，进程退出时清掉）。
- 管理员会话有效期改为 12 小时；`createAdmin` 脚本增加 `--role` 参数。
- 测试：重复注册 409；非法用户名 400；登录错误不区分原因；登出后令牌 401；超过频率 429。

### P1-5 日志、健康检查、配置、优雅停机

- `Fastify({ logger: { level, redact: ["req.headers.authorization", "*.password", "*.token"] }, genReqId })`，每个响应头带 `X-Request-Id`。
- `GET /healthz`：检查数据库 `SELECT 1`，返回 `{ok, version, contentVersion}`。
- `server.ts`：监听 `SIGTERM`/`SIGINT` 调用 `app.close()` 并关闭数据库连接池；`unhandledRejection` 记日志后退出（由 systemd 拉起）。崩溃日志文件保留。
- 去掉代码里 `admin.id === "unused"` 这类测试残留，测试改为创建真实管理员。
- 验收：本机 `kill -TERM` 后进程在 5 秒内正常退出；日志中看不到明文令牌和密码。

### P1-6 数据库迁移基线重建

- 前置：在测试服和正式服各执行一次 `pg_dump -Fc` 备份，文件名带日期，保存到服务器 `/var/backups/xiuxian/` 并下载一份到本机。**未完成备份不得执行后续步骤。**
- 本任务与 P2-1、P3-1 的表结构一起完成：先把 02 §4 的所有表写进 `schema.ts`，删除 `backend/drizzle/` 旧目录，`drizzle-kit generate` 生成新的 `0000` 基线。
- 写 `docs/operations/db-migration.md`：之后改表的唯一流程（改 `schema.ts` → generate → 审查生成的 SQL → 提交 → CI 跑迁移 → 测试服 → 正式服）。
- 验收：在空库上 `db:migrate` 成功；再次 `drizzle-kit generate` 不产生新文件。
- 说明：因为现有数据都是测试数据，正式服直接用新库 `xiuxian_prod` 重建；旧库保留 30 天后删除。

---

## P2 内容配置系统重做

### P2-1 内容草稿表与纯校验函数

- 在 `schema.ts` 按 02 §4.3、§4.4 新建表；删除旧的 `realms`、`skills`、`items`（带 release_id 的）、`content_releases`、`content_documents`。
- 新增 `backend/src/modules/content/snapshot-schema.ts`：zod 定义快照结构，导出类型 `ContentSnapshot`。
- 新增 `backend/src/modules/content/validate.ts`：纯函数 `validateContent(draft: ContentSnapshot, knownSlugs): {errors, warnings}`，覆盖 02 §3.7 全部 9 条规则，每条错误含 `kind`、`slug`、`field`、`message`。
- 测试：每条规则至少一个通过用例和一个失败用例；现有 `publish-rules.test.ts` 中的用例迁移过来。
- 验收：`validate.ts` 不导入任何数据库模块。

### P2-2 草稿增删改查接口

- `backend/src/modules/content/draft-service.ts` + `draft-routes.ts`：按 02 §5.4 实现全局配置、境界、物品、功法、掉落表（含条目）、关卡的 GET 列表、GET 单条、POST 新建、PUT 修改、DELETE（只允许删除 `content_known_slugs` 中不存在的编号）。
- 保存单条时做字段级校验（类型、范围、枚举、引用存在），引用不存在 → 400 并指出字段。
- 每次修改记录 `updated_by`、`updated_at`。
- 测试：每类内容的增改删各一个；删除已发布编号返回 409；引用不存在返回 400。

### P2-3 发布、快照、缓存、版本历史

- `publish(tx, admin, note)`：读全部草稿 → 组装 `ContentSnapshot` → `validateContent` → 有错误则 400 → 计算 checksum → 插入 `content_versions` → 更新 `content_current` → 写入 `content_known_slugs` → 写 `publish` 操作记录。全部在一个事务中，并对 `content_current` 行加锁，防止两个管理员同时发布。
- 新增 `content/runtime.ts`：`getCurrentContent()` 返回内存中缓存的当前快照及按 slug 建好的索引（`realmsBySlug` 等）。发布成功后刷新缓存；进程启动时加载；每 30 秒检查一次 `content_current.version` 是否变化（为将来多进程部署做准备）。
- `restoreDraft(version)`：把某版本快照写回草稿表（先清空草稿表）。
- 公开接口：`GET /api/v1/content/current`、`GET /api/v1/content/versions/:version`（只输出客户端需要的字段，见 02 §4.4）。
- 测试：发布成功后版本号 +1、缓存更新；校验失败时当前版本不变；两个发布并发只成功一个或依次成功、不会出现两个“当前版本”；恢复草稿后再发布，快照内容与原版本一致（版本号不同）。

### P2-4 种子数据导入

- 把 `game/resources/config/idle_rules.json`、`adventure.json` 复制到 `backend/seeds/legacy/`（客户端那份暂不删，P4-8 再删）。
- 新增 `backend/src/scripts/seed-content.ts`（`npm run db:seed`）：清空草稿 → 转换导入 → 打印统计。转换规则：
  - 境界：`gain_per_second` → `tickSeconds = 1`、`gainPerTick = gain_per_second`；`realm_bases` 的攻防血、出手间隔 → 基础属性；突破参数按 02 §2.5 的建议：同一大境界内 `baseRateBp = 9000`，跨大境界 `6000`；凡人 → 炼气初期设为 `10000`（必成功）；`recommendedPower` 先等于下一关卡的 `min_power`，没有则为 0。
  - 关卡：`monsters` 的最后一个作为 Boss；其余怪物中的第一个作为挂机怪；`min_power` → `recommendedPower`；`min_realm_order` → `requiredRealmOrder`；`next_id` → `nextStageSlug`。
  - 掉落：每个关卡生成 `drop_<stage>_boss`（Boss 的掉落）和 `drop_<stage>_idle`（其余怪物掉落合并去重，取最大概率）；概率 `chance × loot_chance_scale × 10000` 四舍五入为万分比，最小 1；`count` → `minQty = maxQty = count`。
  - 首通掉落：每关生成 `drop_<stage>_first`，内容为该关 Boss 掉落中品质最高的一件装备和一本功法书，概率 10000。
  - 物品、功法：字段一一对应，`cultivate_bonus`（小数）× 10000 → `cultivateBonusBp`。
  - 全局配置：`offline_cap_seconds`、`inventory_capacity`、`respawn_seconds`、战力权重默认值。
- 导入后自动运行 `validateContent`，打印错误和警告；有错误时退出码非 0。
- 验收：导入后 `/admin/content/validate` 无错误，可以发布出版本 1。

### P2-5 后台：内容配置页面重写

- 新增依赖：`pinia`、`echarts`（P2-7 用）。
- 新增 `admin/src/stores/draft.ts`：缓存境界/物品/功法/掉落表/关卡的 `{slug, displayName}` 列表，供所有下拉框使用；任何保存成功后刷新。
- 新增通用组件：`SlugSelect.vue`（按类型下拉、可搜索、显示“名称（编号）”）、`PercentInput.vue`（百分比 ↔ 万分比）、`DurationInput.vue`（小时/分钟 ↔ 秒）、`ChangeTag.vue`（新增/已修改/未变）。
- 每类内容一个列表页 + 一个表单弹窗组件：`GlobalsView`、`RealmsView`/`RealmForm`、`ItemsView`/`ItemForm`、`SkillsView`/`SkillForm`、`DropTablesView`/`DropTableForm`、`StagesView`/`StageForm`。删除通用的 `DraftPage.vue`、`DropLinkForm.vue`、`BuildingsView.vue`。
- 表单规则：编号只在新建时可编辑，前端也按 02 §2.1 的正则校验；后端返回的字段错误显示在字段下方。
- 功法页只读显示“功法书”和“掉落来源关卡”；掉落表页只读显示“被哪些关卡引用”。
- 菜单按 02 §7.1 分组。
- 验收：新建一件装备 → 加到某关 Boss 掉落表 → 校验通过 → 发布，全程不需要手打任何编号（新建时的编号除外）。

### P2-6 后台：校验发布页与版本历史页

- `PublishView`：调用 `/content/validate` 和 `/content/diff`，展示错误/警告（点击跳到对应编辑弹窗）、差异列表、发布说明输入框；有错误时发布按钮禁用。
- `VersionsView`：分页列表；查看某版本 JSON（只读、可折叠）；“恢复到草稿”需二次确认，并提示“恢复后需要再发布才会生效”。
- `admin/src/api.ts`：只有 401 跳登录页；403 弹“没有权限”。
- 验收：手工走一遍“改数值 → 看到差异 → 发布 → 版本历史出现新版本 → 恢复上一版到草稿 → 再发布”。

### P2-7 数值工具：成长模拟与战斗模拟

- 后端 `backend/src/modules/tools/`：
  - `simulateGrowth(snapshot, options)` 纯函数：模拟一个理想玩家，策略为“修为够就突破；突破失败按期望值计算（期望尝试次数 = 1 / 成功率，含保底递增）；每到一个境界，假设已穿上该境界可穿的、来自已通关关卡首通掉落的装备”。输出每个境界的累计到达时间、该次突破的成功率、当时战力。
  - `simulateBattle(stats, stageSlug, snapshot)`：调用 P3-6 的战斗纯函数（本任务可先实现战斗纯函数，P3-6 复用）。
  - 接口：`POST /api/v1/admin/tools/simulate-growth`（可选 `version`，不传用草稿）、`POST /api/v1/admin/tools/simulate-battle`。
- 后台 `GrowthSimView`（表格 + echarts 折线图，横轴境界、纵轴累计小时）、`BattleSimView`（输入属性或选择境界自动填基础属性，选关卡，显示胜负、用时、双方每击伤害）。
- 验收：用种子数据跑成长模拟，能看到“第一次突破约 3 分钟”；修改凡人的 `gainPerTick` 后重新模拟，结果随之变化。

---

## P3 服务器核心循环

> 本阶段所有规则先写纯函数和单测，再写 service 和接口。纯函数放 `rules.ts`，不导入数据库。

### P3-1 玩家数据表与状态组装

- 按 02 §4.5 建表（与 P1-6 一起生成迁移）。
- `backend/src/modules/player/state.ts`：`loadPlayerAggregate(tx, playerId, {lock})` 一次读出状态行（可选 `FOR UPDATE`）、物品、功法、关卡进度；`buildStateDto(aggregate, content, now)` 纯函数组装 02 §5.3 的 `state`。
- 注册时按 02 §2.2 初始化（含新手物品、第一关解锁）。
- 测试：新注册玩家的 `state` 字段完整、境界为起始境界、第一关已解锁。

### P3-2 属性与战力

- `backend/src/modules/combat/stats.ts`：`computeStats(aggregate, content) → {attack, defense, hp, speed, interval, power}`，公式见 02 §2.4。
- 黄金值测试：从 `game/tests/unit/test_combat_rules.gd` 中挑至少 5 组输入输出，在 TypeScript 中得到相同结果（允许 0.001 误差）。
- 删除旧的 `player/power.ts`，引用改到新函数。

### P3-3 修为结算与 `/me/sync`

- `progress/rules.ts`：`settleCultivation({cultivation, lastSettledAt, now, tickSeconds, gainPerTick, bonusBp, offlineCapSeconds})`，按 02 §2.3 整数节拍实现，返回新修为、新 `lastSettledAt`、计入秒数、是否触顶。
- `progress/service.ts`：`syncPlayer(tx, playerId, now)`：锁行 → 结算 → 写回 → 若计入秒数 ≥ 300 写 `sync_offline` 记录并生成离线收益弹窗 → 返回 `{state, offlineReport}`。
- 路由 `POST /api/v1/me/sync`。旧的 `GET /me` 别名内部调用 `syncPlayer`，响应结构保持旧格式，直到旧客户端下线。
- 测试：零头秒数不丢失（例如 tick=3 秒，经过 10 秒，得 3 拍，`lastSettledAt` 前进 9 秒）；超过上限时 `lastSettledAt = now`；时间回拨按 0；心法加成生效；连续两次 sync 间隔 1 秒不会重复加修为。

### P3-4 概率突破

- `progress/rules.ts`：`breakthroughRate(...)` 和 `resolveBreakthrough(..., roll)` 纯函数，按 02 §2.5 实现；`roll` 由调用方传入，便于测试。
- service：锁行 → 先 sync → 检查前置条件（返回对应错误码）→ `crypto.randomInt(0, 10000)` → `resolveBreakthrough` → 写回 → 写操作记录（含成功率、骰子点数）。
- 状态 DTO 中的 `breakthrough` 字段使用同一个 `breakthroughRate` 函数计算，保证“显示的成功率 = 实际使用的成功率”。
- 测试：战力等于推荐值时成功率 = `baseRateBp`；高于和低于时按公式变化并被上下限截断；保底叠加；`roll = rate − 1` 成功、`roll = rate` 失败；失败扣除比例正确；`requiredStageSlug` 未通关时返回 `STAGE_REQUIRED`；最高境界返回 `REALM_MAX`。

### P3-5 行囊与装备

- `inventory/rules.ts`：`addItems(aggregate, grants, content, bagCapacity)` 返回要插入/更新的行或 `BAG_FULL`；`equip(aggregate, itemId, content)`、`unequip(aggregate, slot)` 返回变更。
- service + 路由：`POST /me/items/:itemId/equip`、`POST /me/equipment/:slot/unequip`。
- 规则：只能穿装备类；境界不足 `REALM_TOO_LOW`；同部位自动换下；不是自己的物品 404。
- 测试：穿戴后属性和战力变化；同部位替换；境界不足拒绝；可堆叠物品叠加到同一行；满包拒绝。

### P3-6 关卡 Boss 挑战与掉落

- `combat/battle.ts`：`simulateBattle(playerStats, boss, combatConfig) → {win, reason, durationSeconds, log}`，按 02 §2.6 的时间轴实现（P2-7 若已实现则复用）。
- `content/drops.ts`：改为 `rollDropTable(entries, randomInt)`，使用万分比和数量区间。
- `adventure/service.ts` + 路由 `POST /me/stages/:slug/challenge`：锁行 → sync → 校验解锁、境界、冷却 → 检查行囊余量（按掉落表可能产出的最大格数预检，不够返回 `BAG_FULL`）→ 模拟 → 胜利则掷掉落、首通掉落、更新进度、解锁下一关 → 写操作记录 → 返回结果和 `state`。
- 失败时返回“差距提示”：计算在其他属性不变的情况下，攻击需要达到多少才能在时限内获胜（二分查找），或防御需要多少才能撑过。
- 测试：确定性（同样输入同样结果）；玩家攻击低于 Boss 防御 × 0.4 时只造成 1 点伤害；超时判负；首通掉落只发一次；下一关被解锁；冷却期内返回 `CHALLENGE_COOLDOWN`；掉落概率统计测试（固定随机序列）。

### P3-7 功法学习与运转

- `skills/rules.ts`：`learnFromBook(aggregate, itemId, content)`、`runSkill(aggregate, skillSlug, slot, content)`、`stopSkill(...)`。
- 路由：`POST /me/items/:itemId/use`（物品是功法书时走学习）、`POST /me/skills/:slug/run`、`POST /me/skills/:slug/stop`。
- 规则：境界不足、前置未学、已学会、槽位类型不符（心法只能进 `heart`，其他只能进 `art_*`）、槽位超出当前可用数，分别返回对应错误码；运转到已占用槽位时替换原功法。
- 测试：学习消耗一本书；心法运转后修炼速度（`cultivationRate.bonusBp`）变化；武技运转后战力变化；突破到第 4 顺序境界后 `artSlotCount` 变为 2。

### P3-8 幂等键

- 新增 `plugins/idempotency.ts`：对标记为需要幂等的路由，读取 `Idempotency-Key`，缺失返回 400；在业务事务内先查 `idempotency_keys`，存在则直接返回保存的响应；否则执行业务并在同一事务内保存响应。
- 适用路由：突破、挑战、穿戴、卸下、使用物品、运转/停止功法、设置挂机地点。
- 清理：每小时删除 24 小时前的记录。
- 测试：同一个键请求两次突破，只掷一次骰子、只扣一次修为，两次响应相同。

### P3-9 接口集成测试

- `backend/src/e2e/core-loop.test.ts`：用 `app.inject` 走完整流程——导入种子并发布 → 注册 → sync → 用测试时钟推进时间 → 突破成功 → 挑战第 1 关获胜并获得首通装备 → 穿戴 → 战力上升 → 学习功法书 → 运转 → 修炼速度上升。
- 需要把 `now` 和随机数生成器作为依赖注入到 `buildApp`（现在已经注入了 `now`，再加 `randomInt`）。
- 验收：该测试在 CI 中通过。

---

## P4 客户端改为纯展示

> 开始前先读 `.cursor/skills/implement-game-feature/SKILL.md` 和 `.cursor/rules/godot-gdscript.mdc`。每个页面改造完成都要用 Godot 无头模式跑 GUT，并在 1080×1920 窗口里截图确认。

### P4-1 环境配置与异步网络层

- 新增 `game/autoload/app_env.gd`：读取 `xiuxian/network/api_base_url`（含特性标签覆盖），在 `project.godot` 注册为自动加载。
- 新增 `game/autoload/api_client.gd`：按 02 §6.2 实现，内部为每个请求创建一个 `HTTPRequest` 子节点，`await request_completed`，结束后释放。
- 新增 `game/scripts/net/api_errors.gd`：错误码 → 中文提示，与后端 `errors.ts` 一一对应。
- 删除 `player_api.gd`、`published_config.gd` 中的阻塞实现。
- 改 `export_presets.cfg`：两个 Android 预设分别带 `staging`、`prod` 特性标签。
- GUT 测试：错误响应解析、401 触发登出信号、426 触发强制更新信号（用假的 HTTP 层）。
- 验收：网络断开时界面不冻结，3 秒内显示“网络连接失败”。

### P4-2 登录注册页

- 新增 `scenes/pages/login_page.tscn` + `scripts/ui/login_page.gd`（沿用 `player_login.gd` 的视觉）。
- 前端校验与后端一致（用户名 2–16 位等）；勾选“我已阅读并同意用户协议和隐私政策”才能注册（先用占位文本页面）。
- 请求期间按钮显示“登录中…”并禁用；错误显示在按钮下方，使用 `api_errors.gd` 的提示。
- 新增 `game/autoload/auth_session.gd`：令牌保存在 `user://session.dat`（用 `FileAccess.open_encrypted_with_pass`，密码取设备 ID 派生），登出时先调后端 `/auth/logout` 再删本地文件。
- 验收：注册、登录、错误密码、重复用户名、断网五种情况的界面表现正确。

### P4-3 内容缓存与状态仓库

- `game/autoload/content_cache.gd`：启动时 `GET /content/current`；本地有同版本且 checksum 一致则直接用，否则下载并保存；提供 `realm(slug)`、`item(slug)`、`skill(slug)`、`stage(slug)`、`drop_table(slug)` 查询。
- `game/autoload/game_store.gd`：`apply_state(state)`；若 `state.contentVersion` 与缓存不一致，先触发内容更新再发信号；提供插值后的 `display_cultivation()`（02 §6.4）；60 秒定时 sync；监听应用回到前台时 sync。
- GUT 测试：插值计算（零头、上限）；版本不一致时触发内容下载。

### P4-4 拆分主界面

- `main.tscn` 只保留：顶栏（境界、战力、修为）、页面容器、底栏（修炼、历练、行囊、功法 4 个入口 + 顶部设置齿轮）、弹窗层。
- `main_screen.gd` 只负责页面切换和登录态切换，目标 300 行以内。
- 每个页面独立 `tscn + gd`，页面只依赖 `GameStore`、`ContentCache`、`ApiClient`。
- 公用组件：`components/item_cell.tscn`、`item_detail_card.tscn`、`confirm_dialog.tscn`、`loading_mask.tscn`、`toast.gd`。
- 验收：每个页面脚本不超过 400 行；删除 `main_screen.gd` 中所有页面逻辑后游戏仍能启动到登录页。

### P4-5 修炼页

- 显示：境界名（大境界 + 小境界）、插值修为 / 突破消耗、进度条、每拍修为与心法加成、距可突破的预计时间、当前战力、**突破成功率**（低于 50% 时用醒目颜色并提示“提升战力可提高成功率”）、连续失败次数与保底加成、需通关的关卡（如有，可点击跳到历练页）。
- 突破按钮：不可突破时显示原因；点击 → 禁用 → 调接口 → 成功播放现有突破动画并显示新境界名和新速率（修复 01-review S2-15）；失败播放失败效果并显示“损失修为 X，下次成功率 +Y%”。
- 离线收益弹窗：`offlineReport` 存在时显示时长、修为、（P5 起）灵石和物品。
- 验收：插值数字平滑增长；切到后台 10 分钟再回来，数值与服务器一致。

### P4-6 历练页（关卡与 Boss）

- 关卡列表：名称、推荐战力 vs 我的战力（颜色区分）、所需境界、状态（未解锁 / 可挑战 / 已通关）、首通奖励预览（从掉落表读）。
- 挑战：点击 → 调接口 → 战斗回放面板按 `log` 播放（双方血条、伤害飘字，总时长压缩到 3–6 秒，可点击跳过）→ 结果：胜利显示掉落物品；失败显示原因和“差距提示”，并提供“去行囊换装备”“去功法运转”两个按钮。
- 验收：从第 1 关打到第 3 关，掉落进入行囊。

### P4-7 行囊页与功法页

- 行囊：沿用现有夜山背景和纸娃娃五部位布局；格子来自 `state.inventory`，名称/品质/图标来自 `ContentCache`；点击物品弹出详情卡，按钮“穿戴 / 卸下 / 学习（功法书）”调对应接口；显示与当前同部位装备的属性对比（绿升红降）。
- 功法：已学功法列表（按心法/攻法/体法/步法分页签）；运转槽（心法 1 个 + 武技 1–2 个）；点击功法显示属性和“运转到槽位”；未学功法显示“需要功法书：xxx，掉落于：yyy 关”。
- 验收：穿上装备后顶栏战力立即变化；运转心法后修炼页速率立即变化。

### P4-8 下线本地玩法

- 把 02 §6.5 列出的脚本和场景移入 `game/legacy/`，在两个导出预设的排除过滤中加入 `legacy/*`。
- 移除 `main.tscn` 中洞府、门派、远行等节点；底栏只保留 4 个入口。
- 删除 `game/resources/config/*.json`（种子已在 `backend/seeds/`），并删除只测试本地玩法的 GUT 测试，保留与 UI 组件、网络、插值、更新相关的测试。
- 导出包体检查：导出后 APK 中不再包含 `legacy/` 和旧配置 JSON。
- 验收：全仓库客户端代码中不再有写 `user://saves/` 的代码；GUT 全部通过。

### P4-9 网络与异常体验

- 统一的顶部提示条：断网（“网络连接失败，正在重试”）、服务器维护（503）、版本过旧（426 → 强制更新弹窗，复用现有热更新流程）。
- 请求超过 500 毫秒才显示加载遮罩，避免闪烁。
- 设置页：账号名、退出登录、版本号、检查更新、音量。删除“导出存档”。
- 验收：手机开飞行模式操作，各页面都有提示且不崩溃；恢复网络后自动 sync。

---

## P5 挂机打怪与离线收益

### P5-1 挂机结算

- 按 02 §2.10 实现 `adventure/idle-rules.ts`：击杀数、灵石、掉落（含二项分布抽样，抽样函数接受注入的随机数以便测试）。
- 并入 `syncPlayer`：修为和挂机用同一段计入时间、同一个事务。满包时物品跳过并在离线报告中写“行囊已满，X 件物品未拾取”。
- `POST /me/idle-stage`：只能选已通关的关卡。
- 测试：打不过挂机怪时击杀数为 0；击杀上限生效；修为与挂机不重复计时。

### P5-2 灵石与客户端

- 状态 DTO 已有 `spiritStones`；修炼页顶栏显示灵石。
- 历练页每个已通关关卡显示“设为挂机地点”及预计每小时收益（服务器在 `state.stages[]` 中返回 `idleKillsPerHour`、`idleStonesPerHour`）。
- 离线报告弹窗显示修为、灵石、物品列表。
- 说明：灵石第一版没有消耗出口。消耗出口（装备强化或洞府）放在 P8，并在 ADR-0007 中写明。

---

## P6 后台开发辅助

### P6-1 玩家列表与详情

- 列表：分页、按用户名搜索、按境界筛选、按注册时间/最后登录排序；列：用户名、境界、战力、修为、最后登录、状态。用一条 SQL 联表查询，禁止循环查询。
- 详情页：基础状态、属性与战力（服务器现算）、物品（含穿戴）、功法（含运转）、关卡进度、最近 50 条操作记录（可翻页）。

### P6-2 GM 工具（仅测试环境）

- 后端：`ENABLE_GM_TOOLS=true` 时才注册 `/api/v1/admin/gm/*` 路由；只允许 `owner` 角色。功能：发放物品、设置境界、设置修为、重置玩家（删除物品/功法/关卡进度并恢复初始状态）、推进该玩家时间（把 `lastSettledAt` 往前调 N 小时，用于测试离线收益）。每次调用写 `gm_*` 操作记录，含管理员和前后值。
- 后台：玩家详情页右上角“GM 工具”按钮（接口不存在时不显示）。
- 测试：环境变量关闭时这些路由返回 404。

### P6-3 数据看板

- 后台首页：总注册数、今日新增、今日活跃（今日有 sync 的玩家数，从 `sessions.last_seen_at` 统计）、境界分布柱状图、各关卡首通人数。
- 接口 `GET /api/v1/admin/dashboard`，查询结果缓存 60 秒。

---

## P7 上线准备

### P7-1 HTTPS 与 Nginx

- 前置：域名已完成 ICP 备案（项目负责人负责）。未完成时本任务只准备配置文件和文档，不执行切换。
- `tools/deploy/nginx/xiuxian.conf`：`api.<域名>` 反代、`/admin/` 静态文件、HTTP→HTTPS、gzip、请求体大小限制。
- certbot 自动续期；`docs/operations/server-setup.md` 记录完整步骤。
- 客户端 `prod` 特性标签的 API 地址改为 `https://api.<域名>`。

### P7-2 部署脚本与环境拆分

- `tools/deploy/deploy_backend.sh <staging|prod> <git-tag>`、`tools/deploy/deploy_admin.sh <staging|prod>`，步骤见 02 §8.2。
- systemd：`xiuxian-api-staging.service`、`xiuxian-api.service`，各自的环境文件放 `/etc/xiuxian/<env>.env`（不进 Git）。
- 发布流程写进 `docs/operations/release-process.md`：合并到 `main` → 打标签 → 部署测试服 → 冒烟测试清单 → 部署正式服。

### P7-3 备份与恢复

- `tools/deploy/backup_db.sh`：每天 4 点 `pg_dump -Fc`，保留 14 天，上传 OSS。
- 恢复演练脚本与文档：把最新备份恢复到临时库并运行 `/healthz` 等价检查。
- 验收：实际执行一次恢复演练并记录结果。

### P7-4 压测与性能

- 用 k6 写脚本 `tools/loadtest/core_loop.js`：模拟 500 个玩家，每人每 60 秒 sync 一次、每 5 分钟挑战一次关卡、偶尔突破。
- 目标：p95 响应时间 < 200 毫秒，错误率 < 0.1%，数据库连接数稳定。
- 发现慢查询时补索引（用 `EXPLAIN ANALYZE` 确认）。

### P7-5 监控与告警

- 外部可用性监控（例如阿里云云监控或 UptimeRobot）每分钟请求 `/healthz`，失败发短信/邮件。
- 每天汇总 500 错误数量；磁盘使用超过 80% 告警。

### P7-6 客户端版本控制

- 全局配置新增 `minClientVersionCode`；后端中间件按 02 §5.1 返回 426。
- APK 上传改为：后台填写 OSS 下载地址、版本号、sha256、更新说明；`/update.json` 由 API 返回；旧的 GitHub Releases 渠道在新客户端全量后停止更新，并在 `docs/architecture/update-system.md` 中说明。

---

## P8 长线玩法（以后，另行规划）

以下内容不在本轮实施范围，P7 完成后再按“先写设计 → 再写 ADR → 再拆任务”的流程推进：

- 灵石消耗出口：装备强化（推荐最先做，最简单的灵石出口）。
- 功法参悟（升级）、重复功法书的去处。
- 丹药（修炼加速、突破成功率加成）。
- ADR-0005 的洞府（灵田、丹房、器室、藏经阁），在服务器上按“队列 + 统一结算时间”重做。
- 门派、排行榜、斗法、聊天。
- 实名认证与防沉迷接入。

---

## 依赖关系

```text
P0 ──▶ P1 ──▶ P2-1 ─▶ P2-2 ─▶ P2-3 ─▶ P2-4 ─▶ P2-5 ─▶ P2-6
                │                         │
                └──── P1-6（与 P2-1、P3-1 一起生成迁移）
                                          ▼
                       P3-1 ─▶ P3-2 ─▶ P3-3 ─▶ P3-4 ─▶ P3-5 ─▶ P3-6 ─▶ P3-7 ─▶ P3-8 ─▶ P3-9
                                                                  │
                                                         P2-7（复用战斗纯函数）
P3-9 ──▶ P4-1 ─▶ P4-2 ─▶ P4-3 ─▶ P4-4 ─▶ P4-5 ─▶ P4-6 ─▶ P4-7 ─▶ P4-8 ─▶ P4-9
P4-9 ──▶ P5 ──▶ P6 ──▶ P7
```

可并行：P0-4 与 P0-3；P2-5 的后台页面可在 P2-2 接口完成后与 P2-3 并行；P6-1 可在 P3 完成后随时开始。
