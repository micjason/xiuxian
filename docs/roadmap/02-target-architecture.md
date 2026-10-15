# 02 目标架构与设计规格

本文件是后续实现的唯一依据。执行代理实现任何任务时，规则、字段、接口以本文件为准；本文件没写到的，先补本文件再写代码。

---

## 1. 总体结构

```text
┌──────────────┐   HTTPS / JSON    ┌───────────────────────────┐    SQL    ┌──────────────┐
│ game/ 手机端 │ ───────────────▶ │ backend/ 游戏服务器        │ ───────▶ │ PostgreSQL   │
│ Godot 4.7.2  │ ◀─────────────── │ Fastify + Drizzle          │ ◀─────── │ (同机，只监听 │
│ 只展示和操作 │   玩家状态快照     │ 结算、战斗、掉落、发布      │          │  127.0.0.1)  │
└──────────────┘                   └───────────────────────────┘           └──────────────┘
                                            ▲
                                            │ HTTPS / JSON（管理员会话）
                                   ┌───────────────────┐
                                   │ admin/ 管理后台    │
                                   │ Vue 3 + Element+  │
                                   │ 编辑草稿、发布、   │
                                   │ 查玩家、GM 工具    │
                                   └───────────────────┘
```

### 1.1 三端职责（硬边界）

| 端 | 负责 | 绝不做 |
|---|---|---|
| 手机端 `game/` | 登录注册页面；拉取内容快照并缓存；拉取玩家状态并渲染；本地插值显示修为增长；播放战斗回放和动画；把玩家操作（突破、挑战、穿戴、学习）发给服务器 | 计算修为、掉落、战斗胜负、突破成败；在本地保存进度；把本地数值上传给服务器 |
| 后端 `backend/` | 账号与会话；读取已发布内容；所有结算与随机；所有进度写入；发布内容；操作记录；给后台提供管理接口 | 渲染；信任客户端传来的任何数值 |
| 后台 `admin/` | 编辑内容草稿；校验和发布；版本历史与回滚；查看玩家；（仅测试环境）GM 工具；数值模拟 | 直接写数据库；绕过后端接口 |

### 1.2 一条请求的完整生命周期（以“突破”为例）

1. 玩家点“突破”。手机端立即禁用按钮，生成一个幂等键（UUID），调用 `POST /api/v1/me/breakthrough`。
2. 后端鉴权插件根据 `Authorization` 头找到玩家。
3. 开启数据库事务 → `SELECT ... FOR UPDATE` 锁住该玩家的状态行 → 先做一次修为结算（把上次结算到现在的修为补上）→ 读取当前已发布内容（内存缓存）→ 调用纯函数计算成功率并掷骰 → 写回进度 → 写操作记录 → 提交事务。
4. 返回 `{ result: {...}, state: <完整玩家状态> }`。
5. 手机端用返回的 `state` 整体替换本地状态仓库，播放成功或失败动画，恢复按钮。

---

## 2. 核心玩法规格

> 所有数值都来自后台发布的内容快照。下文中的“配置项”就是后台要能编辑的字段。

### 2.1 名词

| 名词 | 编号风格 | 含义 |
|---|---|---|
| 修为 | — | 主资源，随时间增长，用于突破。整数 |
| 灵石 | — | 通用货币（第 5 阶段起用），击杀和首通获得。整数 |
| 境界 | `mortal`、`qi_early`… | 玩家等级。决定每秒修为、基础属性、可穿戴装备和可学功法 |
| 战力 | — | 由最终属性算出的一个整数，影响突破成功率和关卡推荐 |
| 关卡 | `grove`、`boar_slope`… | 有一个 Boss；首通后解锁下一关；Boss 掉高阶装备和功法书 |
| 物品 | `sword_0`、`book_tuna`… | 四类：装备、功法书、丹药、材料 |
| 功法（技能） | `tuna`… | 四类：心法（加修炼速度）、攻法、体法、步法（加战斗属性） |
| 掉落表 | `drop_grove_boss`… | 一组“物品 + 概率 + 数量”的条目，被关卡引用 |
| 内容快照 | 版本号 1、2、3… | 一次发布产生的不可变整份内容 |

编号（slug）规则：小写字母、数字、下划线，2–48 位，正则 `^[a-z][a-z0-9_]{1,47}$`。编号一旦发布过就不能删除、不能改名，只能改名称和数值，或标记“停用”。

### 2.2 新玩家

- 注册成功时，在同一事务中创建：账号、玩家状态（境界 = 全局配置 `startingRealmSlug`，默认 `mortal`；修为 0；灵石 0；上次结算时间 = 现在）、新手物品（全局配置 `starterItems`，可为空）、第一个关卡设为已解锁。
- 首次进入游戏直接是修炼页。

### 2.3 修为结算（按整数节拍）

后台按“每 `tickSeconds` 秒获得 `gainPerTick` 点修为”配置每个境界（这就是需求里的“每多长时间获取多少灵气”）。

```text
实际每拍修为 = floor(gainPerTick × (10000 + 心法修炼加成万分比合计) / 10000)
经过秒数     = 服务器当前时间 − lastSettledAt
计入秒数     = min(经过秒数, offlineCapSeconds)
拍数         = floor(计入秒数 / tickSeconds)
新修为       = 修为 + 拍数 × 实际每拍修为
新 lastSettledAt:
  若经过秒数 > offlineCapSeconds：= 现在（超出上限的部分作废）
  否则：= lastSettledAt + 拍数 × tickSeconds（不足一拍的零头留到下次，不丢失）
```

- 时钟只用服务器时间。经过秒数为负（服务器时间回拨）时按 0 处理，并写一条警告日志。
- 修为满了也继续累积，不设上限（突破消耗后多余的保留）。
- 结算触发时机：`POST /me/sync`，以及每个会改变进度的动作开头（突破、挑战、穿戴、学功法前都先结算，保证用的是最新数值）。
- **不再每 5 秒结算。** 客户端每 60 秒、应用回到前台时、每次操作后调用 sync；中间的数字由客户端本地插值显示（见 §6.4）。

### 2.4 战斗属性与战力

最终属性 = 境界基础属性 + 已穿戴装备属性之和 + 已运转功法属性之和，然后应用套装加成（第一版可不做套装）。

```text
攻击 attack、防御 defense、气血 hp、速度 speed：直接相加
出手间隔 interval = max(globals.minInterval, realm.baseInterval × 100 / (100 + max(speed, 0)))
战力 power = round(attack × wAtk + defense × wDef + hp × wHp + speed × wSpd)
默认权重：wAtk = 1.0，wDef = 0.8，wHp = 0.04，wSpd = 1.5，minInterval = 0.7
```

以上公式与现有客户端 `game/scripts/adventure/combat_stats.gd` 一致。服务器实现必须写一组“黄金值”测试，用客户端现有单测中的数值做对照。

### 2.5 突破（有概率，战力越高越容易）

每个境界配置以下字段（都在“境界”页面编辑）：

| 字段 | 含义 | 默认值示例 |
|---|---|---|
| `breakthroughCost` | 突破消耗修为 | 360 |
| `requiredStageSlug` | 必须先通关的关卡，可为空 | 空 |
| `recommendedPower` | 推荐战力，0 表示战力不影响成功率 | 40 |
| `baseRateBp` | 战力刚好等于推荐值时的成功率（万分比） | 9000 |
| `powerFactorBp` | 战力每高出推荐值 100%，成功率增加多少万分比 | 3000 |
| `minRateBp` / `maxRateBp` | 成功率上下限（不含保底） | 2000 / 9500 |
| `failLossBp` | 失败时损失突破消耗的比例（万分比） | 3000 |
| `pityStepBp` | 每连续失败一次，下次成功率增加多少万分比 | 1000 |

```text
前置条件（任一不满足则不能尝试，按钮显示原因）：
  有下一境界；修为 ≥ breakthroughCost；requiredStageSlug 为空或已通关

ratio  = recommendedPower > 0 ? clamp(power / recommendedPower, 0, 3) : 1
rateBp = baseRateBp + round((ratio − 1) × powerFactorBp)
rateBp = clamp(rateBp, minRateBp, maxRateBp)
rateBp = min(10000, rateBp + failStreak × pityStepBp)

roll = 服务器安全随机整数 [0, 10000)
成功：roll < rateBp
  修为 −= breakthroughCost；境界 = nextRealm；failStreak = 0
  重新检查功法运转是否仍合法（不会因升级变得不合法，这里只是保险）
失败：
  修为 −= floor(breakthroughCost × failLossBp / 10000)；failStreak += 1；境界不变
```

- 成功率在突破前就通过玩家状态返回给客户端（`breakthrough.successRateBp`），界面显示“成功率 72%”。这是让玩家理解“提升战力 → 更容易突破”这条循环的关键，必须展示。
- 操作记录里写：境界前后、修为前后、成功率、骰子点数、连续失败次数。
- 推荐配置思路：同一大境界内的小突破成功率高（90% 左右）；跨大境界（如炼气圆满 → 筑基初期）成功率低（60% 左右）、推荐战力高、并要求通关对应关卡。这样玩家在大境界关口会被引导去打关卡、换装备、学功法。

### 2.6 关卡与 Boss 挑战

每个关卡配置：

| 字段 | 含义 |
|---|---|
| `slug`、`displayName`、`sortOrder` | 编号、名称、顺序 |
| `nextStageSlug` | 首通后解锁的下一关（链式，最后一关为空） |
| `requiredRealmOrder` | 挑战所需最低境界顺序 |
| `recommendedPower` | 推荐战力（仅显示和提示用） |
| `boss` | 名称、攻击、防御、气血、出手间隔 |
| `bossDropTableSlug` | Boss 每次胜利都掷一次的掉落表 |
| `firstClearDropTableSlug` | 仅首通时额外掷一次的掉落表（用于保证首通必得关键装备/功法书），可为空 |
| `idleMonster` / `idleDropTableSlug` / `idleStoneMin` / `idleStoneMax` | 挂机用（第 5 阶段才启用） |
| `timeLimitSeconds` | 战斗模拟时长上限，默认 60 |

挑战流程（`POST /me/stages/:slug/challenge`）：

1. 校验：关卡已解锁、境界满足。
2. 用玩家最终属性和 Boss 属性做战斗模拟（与客户端现有 `CombatRules.time_to_kill / time_to_die` 公式一致）：

```text
每击伤害 = 攻击 × 攻击 ÷ (攻击 + k × 对方防御)，k 是全局配置 combat.defenseConstant
按时间轴推进：双方各按自己的出手间隔出手，先把对方气血打到 0 的一方胜。
同一时刻双方同时出手时，玩家先手。
超过 timeLimitSeconds 仍未分胜负 → 判负（提示“输出不足”）。
```

3. 生成战斗日志：每次出手一条 `{t, side, damage, targetHpAfter}`，最多 200 条（超出时只保留开头 100 条和结尾 100 条），供手机播放。
4. 胜利：掷 Boss 掉落表；若首通再掷首通掉落表；标记关卡已通关；解锁 `nextStageSlug`。
5. 失败：无惩罚，返回失败原因（输出不足 / 被击败），并给出“差距提示”：例如“攻击不足：需要约 X 攻击才能在 60 秒内击败”。
6. 第一版不限制挑战次数，但同一玩家两次挑战间隔至少 2 秒（服务端校验，防止脚本刷）。

战斗完全确定（不含暴击等随机），这样玩家能通过“提高战力”稳定地赢，掉落才是唯一的随机。第一版不要加暴击、闪避。

### 2.7 掉落

- 掉落表由多个条目组成：`itemSlug`、`chanceBp`（0–10000 万分比）、`minQty`、`maxQty`。
- 规则：每个条目独立掷一次 `randomInt(0,10000) < chanceBp`，命中后数量在 `[minQty, maxQty]` 内均匀取整。
- 背包满时：装备类不入包，改为放入“待领取邮件”（第一版可简单处理为：拒绝挑战并提示“行囊已满”）。推荐第一版用“行囊已满不能挑战”，规则最简单。
- 首通掉落表建议配置为 100% 必得，用来保证主线关键装备和功法书不会因为运气差卡死（行业通用的“保底”）。
- 所有掉落结果写操作记录（物品、数量、来源关卡）。

### 2.8 装备

- 六个部位：`weapon` 武器、`helmet` 头盔、`clothes` 衣服、`gloves` 护手、`shoes` 鞋子、`accessory` 玉佩（2026-10-15 新增 `gloves`，见 `docs/changes/2026-10-15/`）。
- 五个品质：`white`、`blue`、`purple`、`gold`、`red`（与客户端 `QualityId` 一致）。
- 字段：部位、品质、攻击、防御、气血、速度、`requiredRealmOrder`（穿戴所需境界）、`setSlug`（可空，套装预留）。
- 装备不可堆叠：每件装备是一条独立的玩家物品记录；其他物品按数量堆叠。
- 穿戴：同部位已有装备则自动换下放回行囊。境界不够不能穿。
- 第一版不做强化、洗练、分解。重复装备的去处留到洞府阶段（ADR-0005 的器室）。

### 2.9 功法与功法书

- 四类角色：`heart` 心法、`attack` 攻法、`body` 体法、`step` 步法（与客户端 `SkillRole` 一致）。四个品阶：`huang`、`xuan`、`di`、`tian`。
- 字段：攻击、防御、气血、速度、`cultivateBonusBp`（修炼加成万分比，主要给心法）、`requiredRealmOrder`、`prerequisiteSkillSlugs`（前置功法）。
- 功法书是一种物品（`kind = skill_book`），字段 `skillSlug` 指向一门功法，一门功法最多对应一本书。
- 学习：使用功法书 → 校验境界、前置功法、未学过 → 消耗 1 本书 → 玩家获得该功法。已学过时第一版提示“已学会”，不消耗。
- 运转槽：心法 1 个；武技槽（攻法/体法/步法共用）数量由全局配置按境界决定，默认“境界顺序 ≥ 4 时 2 个，否则 1 个”（与客户端 `SkillRole.art_slot_count` 一致）。只有运转中的功法计入属性和修炼加成。
- 第一版不做功法升级（参悟）。

### 2.10 挂机打怪（第 5 阶段）

- 玩家选择一个已通关的关卡作为挂机地点。
- 每次结算时与修为同一段时间：`击杀耗时 = time_to_kill(玩家, 挂机怪) + respawnSeconds`；若玩家打不过挂机怪则击杀数为 0。`击杀数 = floor(计入秒数 / 击杀耗时)`，单次结算最多 `idleKillCap`（默认 2000）。
- 每次击杀得灵石 `[idleStoneMin, idleStoneMax]`，并对挂机掉落表掷骰。击杀数大于 200 时改用二项分布抽样一次性算出每个条目的命中次数，避免循环过多。
- 回到游戏时弹出“离线收益”：时长、修为、灵石、物品。

### 2.11 良性循环与节奏目标

```text
挂机得修为 ──▶ 修为够了尝试突破 ──失败（战力不足，成功率低）──▶ 去关卡打 Boss
     ▲                    │                                         │
     │                成功 ▼                                         ▼
     └──── 新境界：每秒修为更高、基础属性更高 ◀── 穿装备、学功法、战力提升 ◀── Boss 掉装备和功法书
```

节奏参考（初版数值目标，用后台“数值模拟”页校验）：

| 时间 | 目标 |
|---|---|
| 3 分钟 | 第一次突破（凡人 → 炼气初期），必成功 |
| 30 分钟 | 通关前 2 关，穿上第一套白装，学会第一门心法 |
| 第 1 天 | 炼气圆满，第一次遇到低成功率的大境界突破 |
| 第 2–3 天 | 筑基 |
| 第 7 天 | 金丹初期 |

---

## 3. 后台可配置内容（内容草稿）

所有内容都是“草稿 → 校验 → 发布”。后台每个页面就是下面一张表。“控件”一列是后台表单应该用的输入方式。

### 3.1 全局配置（单条记录）

| 字段 | 类型 | 控件 | 说明 |
|---|---|---|---|
| `startingRealmSlug` | 编号 | 下拉选境界 | 新玩家初始境界 |
| `offlineCapSeconds` | 整数 | 数字（以小时输入） | 离线收益上限，默认 8 小时 |
| `bagCapacity` | 整数 | 数字 | 行囊格数，默认 100 |
| `starterItems` | 列表 | 物品下拉 + 数量 | 新手物品 |
| `powerWeights` | 4 个小数 | 数字 | 战力权重，见 §2.4 |
| `combat` | 若干小数 | 数字 | `minInterval`、`playerDefenseFactor`、`bossDefenseFactor`、`respawnSeconds`、`challengeCooldownSeconds` |
| `artSlotRules` | 列表 | 表格 | `[{minRealmOrder:0, slots:1}, {minRealmOrder:4, slots:2}]` |
| `idleKillCap` | 整数 | 数字 | 第 5 阶段用 |

### 3.2 境界

`slug`、`displayName`、`majorName`（大境界名，如“炼气”，用于界面分组）、`sortOrder`、`nextRealmSlug`（下拉）、`tickSeconds`、`gainPerTick`、`baseAttack`、`baseDefense`、`baseHp`、`baseSpeed`、`baseInterval`、突破字段（见 §2.5）、`enabled`。

### 3.3 物品

`slug`、`displayName`、`description`、`kind`（下拉：equipment / skill_book / pill / material）、`quality`（下拉）、`slot`（仅装备，下拉）、`attack`、`defense`、`hp`、`speed`、`requiredRealmOrder`、`skillSlug`（仅功法书，下拉）、`stackable`（装备固定为否）、`iconKey`（客户端图标名）、`enabled`。表单按 `kind` 显示/隐藏字段。

### 3.4 功法

`slug`、`displayName`、`description`、`role`（下拉）、`rank`（下拉）、`attack`、`defense`、`hp`、`speed`、`cultivateBonusBp`、`requiredRealmOrder`、`prerequisiteSkillSlugs`（多选下拉）、`enabled`。页面只读显示“由哪本功法书学习、这本书从哪些关卡掉落”。

### 3.5 掉落表

`slug`、`displayName`、条目列表 `[{itemSlug（下拉）, chanceBp（以百分比输入，两位小数）, minQty, maxQty}]`。页面只读显示“被哪些关卡引用”。

### 3.6 关卡

见 §2.6 字段表。Boss 属性旁边实时显示“Boss 战力”和“推荐战力玩家能否打赢”的预估（调用后端模拟接口）。

### 3.7 发布校验规则（全部通过才能发布，失败时逐条列出“哪一条、哪个字段、什么问题”）

1. 每个编号符合格式且在各自类型内唯一。
2. 境界：至少 1 个；`nextRealmSlug` 连成唯一一条链（只有一个起点、一个终点、无环、无分叉）；`startingRealmSlug` 是链的起点；`tickSeconds ≥ 1`；`gainPerTick ≥ 0`；`breakthroughCost ≥ 0`；`0 ≤ minRateBp ≤ baseRateBp ≤ maxRateBp ≤ 10000`；`requiredStageSlug` 存在。
3. 关卡：`nextStageSlug` 连成链；引用的掉落表存在；Boss 气血 > 0、出手间隔 > 0。
4. 掉落表：引用的物品存在；`0 ≤ chanceBp ≤ 10000`；`1 ≤ minQty ≤ maxQty`。
5. 物品：装备必须有合法部位；功法书必须指向存在的功法；一门功法最多一本书；`starterItems` 中的物品存在。
6. 功法：前置功法存在且无环。
7. 已在任一历史版本中发布过的编号，不能从草稿中消失（只能 `enabled = false`）。
8. 被停用（`enabled = false`）的物品不能出现在掉落表和新手物品里。
9. 警告（不阻止发布，但要显示）：功法没有任何功法书；功法书不在任何掉落表里；某境界突破在“推荐战力”下成功率低于 30%。
10. 错误（阻止发布）：高一个境界的关卡，推荐战力要高于低一个境界的所有关卡。推荐战力按第一个首领自动算出。

---

## 4. 数据库设计

### 4.1 约定

- 所有表名、列名用 `snake_case`；主键 `uuid` 默认 `gen_random_uuid()`，内容表用 `slug` 作业务键。
- 时间统一 `timestamptz`。
- 修为、灵石、数量用 `bigint`（Drizzle 用 `{ mode: "number" }`，在结算函数里断言结果不超过 `Number.MAX_SAFE_INTEGER`）。属性数值用 `double precision`。概率用 `integer` 万分比。
- 所有表结构改动只能通过修改 `schema.ts` 再 `drizzle-kit generate` 生成迁移；禁止手写迁移 SQL，禁止修改已执行过的迁移文件。
- 每个外键列都要建索引。

### 4.2 账号与会话

**players**：`id`、`username`（唯一，2–16 位，中文/字母/数字/下划线）、`password_hash`、`status`（`active` / `banned`，默认 active）、`created_at`、`last_login_at`。

**admins**：`id`、`username`（唯一）、`password_hash`、`role`（`owner` / `designer` / `viewer`）、`created_at`、`last_login_at`。

**sessions**：`id`、`token_hash`（唯一）、`actor_type`、`actor_id`、`created_at`、`expires_at`、`last_seen_at`、`revoked_at`、`client_info`（版本号、平台）。索引 `(actor_type, actor_id)`、`(expires_at)`。玩家会话 30 天、管理员会话 12 小时；每天清理过期和已撤销的会话。

### 4.3 内容草稿（后台编辑的表，只有一份草稿，不带版本号）

- `content_globals`（单行，`id = 1`，各字段见 §3.1，复杂字段用 `jsonb`）
- `content_realms`
- `content_items`
- `content_skills`
- `content_drop_tables`（`slug`、`display_name`）
- `content_drop_entries`（`drop_table_slug`、`item_slug`、`chance_bp`、`min_qty`、`max_qty`，唯一 `(drop_table_slug, item_slug)`）
- `content_stages`（Boss 属性拆成列：`boss_name`、`boss_attack`…）

每张草稿表都有 `updated_at`、`updated_by`（管理员 id）。

### 4.4 内容版本（发布产物，不可变）

**content_versions**：`version`（`serial` 主键，1、2、3…）、`snapshot`（`jsonb`，整份内容）、`checksum`（快照的 SHA-256）、`note`（发布说明，必填）、`published_by`、`published_at`、`source_version`（回滚时记录来源版本，可空）。

**content_current**：单行，`version` 指向当前生效的版本。发布 = 在同一事务里插入一行 `content_versions` 并更新 `content_current`。

**content_known_slugs**：`kind`、`slug`，主键 `(kind, slug)`。每次发布把快照里的所有编号写入（`ON CONFLICT DO NOTHING`），用于校验规则 7，替代现在“遍历所有历史版本逐个查询”的做法。

快照 JSON 结构（客户端和服务器共用同一种格式，字段用 camelCase）：

```json
{
  "version": 12,
  "globals": { "startingRealmSlug": "mortal", "offlineCapSeconds": 28800, "...": "..." },
  "realms": [ { "slug": "mortal", "displayName": "凡人", "...": "..." } ],
  "items": [ ],
  "skills": [ ],
  "dropTables": [ { "slug": "drop_grove_boss", "entries": [ { "itemSlug": "sword_0", "chanceBp": 1400, "minQty": 1, "maxQty": 1 } ] } ],
  "stages": [ ]
}
```

在 `backend/src/modules/content/snapshot-schema.ts` 里用 zod 定义这份结构并导出 TypeScript 类型；后端读快照时用它校验；同时导出一份 JSON Schema 文件到 `docs/roadmap/content-snapshot.schema.json` 给客户端参考。

### 4.5 玩家数据

**player_states**（一人一行）：`player_id`（主键）、`realm_slug`、`cultivation`（bigint）、`spirit_stones`（bigint）、`last_settled_at`、`breakthrough_fail_streak`（int）、`idle_stage_slug`（可空）、`last_challenge_at`（可空）、`state_version`（int，每次写入 +1，用于排查并发问题）。

**player_items**：`id`、`player_id`、`item_slug`、`is_stack`（boolean：可堆叠物品为 true，装备为 false）、`quantity`（bigint，装备恒为 1）、`equipped_slot`（可空）、`acquired_at`、`source`（`drop:<stage>` / `starter` / `gm`）。索引：
- `(player_id)` 普通索引；
- `(player_id, equipped_slot)` 部分唯一索引，条件 `equipped_slot IS NOT NULL`（同一部位只能穿一件）；
- `(player_id, item_slug)` 部分唯一索引，条件 `is_stack = true`（同一种可堆叠物品只有一行，靠 `quantity` 累加）。

数量减到 0 时删除该行。行囊占用格数 = 未穿戴的行数。

**player_skills**：`player_id`、`skill_slug`、`learned_at`、`running_slot`（可空：`heart` / `art_1` / `art_2`）。主键 `(player_id, skill_slug)`；部分唯一索引 `(player_id, running_slot) WHERE running_slot IS NOT NULL`。

**player_stage_progress**：`player_id`、`stage_slug`、`unlocked_at`、`first_cleared_at`（可空）、`clear_count`、`best_clear_seconds`。主键 `(player_id, stage_slug)`。

### 4.6 审计、幂等与系统

**operation_records**（保留现有表，扩展）：增加 `content_version`（int）、`request_id`、`ip`；`action` 改为 `text` 加应用层枚举（避免每加一个动作都要改数据库枚举）。动作清单：`register`、`login`、`logout`、`sync_offline`、`breakthrough`、`challenge`、`equip`、`unequip`、`learn_skill`、`run_skill`、`publish`、`rollback`、`gm_*`、`repair`。索引 `(actor_id, at desc)`、`(actor_name, at desc)`、`(action, at desc)`。
- `sync` 只有当计入秒数 ≥ 300（玩家离线回来）时才写一条 `sync_offline`；普通 60 秒心跳不写操作记录。
- 保留 180 天，每天任务删除更早的记录（或按月分区，玩家量大时再做）。

**idempotency_keys**：`player_id`、`key`、`endpoint`、`response`（jsonb）、`created_at`。主键 `(player_id, key)`。同一键重复请求直接返回已保存的响应；24 小时后清理。

**repair_previews / repair_applications**：保留现状。

**popup_types / announcements / notice_dismissals / player_notices / app_releases**：保留，归入“运营”模块。`player_notices` 加索引 `(player_id)`。

### 4.7 迁移策略

当前数据库只有测试数据，且迁移文件已与快照不一致（见 01-review S2-8）。按任务 `P1-6` 执行一次性重建：先 `pg_dump` 完整备份 → 删除旧迁移目录 → 用新 `schema.ts` 生成全新的 `0000` 基线 → 在测试服验证 → 再在正式服执行。之后严格只走 `drizzle-kit generate`。旧的手机本地存档不迁入账号（写入 ADR-0007）。

---

## 5. 接口约定

### 5.1 通用约定

- 前缀：`/api/v1`。旧路径（`/me`、`/auth/*`、`/content/published`）在新客户端发布前保留为别名，新客户端全量后删除。
- 请求和响应都是 JSON，字段 camelCase，时间用 ISO 8601 字符串。
- 每个接口都用 zod 定义请求 schema（`fastify-type-provider-zod`），不合法直接 400。
- 请求头：`Authorization: Bearer <token>`；`X-Client-Version: <versionCode>`；`X-Request-Id`（可选，没有则服务器生成）；会改变进度的玩家接口必须带 `Idempotency-Key: <uuid>`。
- 客户端版本低于全局配置 `minClientVersionCode` 时，所有玩家接口返回 426 + 错误码 `CLIENT_TOO_OLD`。
- 成功响应：直接返回数据对象。
- 失败响应统一格式：

```json
{ "error": { "code": "NOT_ENOUGH_CULTIVATION", "message": "修为不足", "details": { } } }
```

| HTTP | 用途 | 常见错误码 |
|---|---|---|
| 400 | 参数不合法 / 发布校验失败 | `INVALID_INPUT`、`IDEMPOTENCY_KEY_REQUIRED`、`PUBLISH_REJECTED` |
| 401 | 未登录、会话过期、账号或密码错误 | `UNAUTHORIZED`、`SESSION_EXPIRED`、`INVALID_CREDENTIALS` |
| 403 | 无权限 / 被封禁 | `FORBIDDEN`、`ACCOUNT_BANNED` |
| 404 | 资源不存在 | `NOT_FOUND` |
| 409 | 状态冲突 / 业务条件不满足 | `USERNAME_TAKEN`、`SLUG_PUBLISHED`、`NOT_ENOUGH_CULTIVATION`、`REALM_MAX`、`STAGE_REQUIRED`、`STAGE_LOCKED`、`REALM_TOO_LOW`、`BAG_FULL`、`NOT_EQUIPMENT`、`NOT_SKILL_BOOK`、`ALREADY_LEARNED`、`PREREQUISITE_MISSING`、`SKILL_NOT_LEARNED`、`SKILL_SLOT_INVALID`、`CHALLENGE_COOLDOWN`、`STAGE_NOT_CLEARED` |
| 426 | 客户端过旧 | `CLIENT_TOO_OLD` |
| 429 | 请求过于频繁 | `RATE_LIMITED` |
| 500 | 服务器错误 | `INTERNAL`（不暴露内部信息） |
| 503 | 没有已发布内容 | `CONTENT_NOT_PUBLISHED` |

错误码清单集中定义在 `backend/src/shared/errors.ts`，客户端 `game/scripts/net/api_errors.gd` 维护同一份中文提示映射。

### 5.2 玩家接口

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/v1/auth/register` | `{username, password, agreeTerms: true}` → `{token, state}` |
| POST | `/api/v1/auth/login` | `{username, password}` → `{token, state}`；失败统一 `INVALID_CREDENTIALS` |
| POST | `/api/v1/auth/logout` | 撤销当前会话 |
| GET | `/api/v1/content/current` | `{version, checksum}`，不需要登录 |
| GET | `/api/v1/content/versions/:version` | 快照全文，强缓存（`Cache-Control: public, max-age=31536000, immutable`） |
| POST | `/api/v1/me/sync` | 结算并返回 `{state, offlineReport?}` |
| POST | `/api/v1/me/breakthrough` | → `{result: {success, rateBp, roll, lostCultivation}, state}` |
| POST | `/api/v1/me/stages/:slug/challenge` | → `{result: {win, reason, durationSeconds, log[], drops[], firstClear, hint}, state}` |
| POST | `/api/v1/me/items/:itemId/equip` | → `{state}` |
| POST | `/api/v1/me/equipment/:slot/unequip` | → `{state}` |
| POST | `/api/v1/me/items/:itemId/use` | 功法书 = 学习；丹药 = 生效（第一版丹药可不做） → `{result, state}` |
| POST | `/api/v1/me/skills/:slug/run` | `{slot: "heart" | "art_1" | "art_2"}` → `{state}` |
| POST | `/api/v1/me/skills/:slug/stop` | → `{state}` |
| POST | `/api/v1/me/idle-stage` | `{stageSlug}`（第 5 阶段） |
| GET | `/api/v1/me/notices` / POST `/api/v1/me/notices/:id/dismiss` | 保留现有弹窗队列 |

### 5.3 玩家状态 `state`（每个玩家接口都返回完整状态）

放置游戏的单个玩家状态很小（几十条物品），每次返回整份状态，客户端整体替换，最简单、最不容易出错。

```json
{
  "serverTime": "2026-10-08T10:00:00.000Z",
  "contentVersion": 12,
  "player": { "id": "…", "username": "张三" },
  "realm": { "slug": "qi_early", "nextSlug": "qi_mid" },
  "cultivation": 1200,
  "spiritStones": 0,
  "cultivationRate": { "tickSeconds": 1, "gainPerTick": 4, "bonusBp": 800 },
  "lastSettledAt": "2026-10-08T09:59:58.000Z",
  "offlineCapSeconds": 28800,
  "stats": { "attack": 30, "defense": 18, "hp": 120, "speed": 0, "interval": 1.45, "power": 61 },
  "breakthrough": {
    "cost": 1260, "canAttempt": false, "blockedReason": "NOT_ENOUGH_CULTIVATION",
    "successRateBp": 8200, "failLossBp": 3000, "failStreak": 0, "requiredStageSlug": null
  },
  "inventory": [ { "id": "…", "itemSlug": "sword_0", "quantity": 1, "equippedSlot": "weapon" } ],
  "bagUsed": 12, "bagCapacity": 100,
  "skills": [ { "skillSlug": "tuna", "runningSlot": "heart" } ],
  "artSlotCount": 1,
  "stages": [ { "stageSlug": "grove", "unlocked": true, "firstClearedAt": null, "clearCount": 0 } ],
  "idleStageSlug": null
}
```

名称、描述、图标不放进状态里，客户端用 `contentVersion` 对应的内容快照按 `slug` 查。若 `state.contentVersion` 与客户端缓存不一致，客户端先下载新快照再渲染。

### 5.4 后台接口（全部需要管理员会话，前缀 `/api/v1/admin`）

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/auth/login`、`/auth/logout` | 管理员登录登出 |
| GET/PUT | `/content/globals` | 全局配置 |
| GET/POST/PUT/DELETE | `/content/{realms,items,skills,drop-tables,stages}[/:slug]` | 草稿增删改查；DELETE 只允许删从未发布过的编号 |
| GET | `/content/validate` | 对当前草稿运行全部发布校验，返回 `{errors[], warnings[]}`，每条含 `kind、slug、field、message` |
| GET | `/content/diff` | 草稿与当前版本的差异 |
| POST | `/content/publish` | `{note}`，校验通过才发布 |
| GET | `/content/versions` | 版本列表（分页） |
| GET | `/content/versions/:version` | 某版本全文 |
| POST | `/content/versions/:version/restore-draft` | 把某个历史版本复制回草稿（之后再走一次发布 = 回滚） |
| POST | `/tools/simulate-growth` | 输入草稿或某版本，输出“理想玩家”到达每个境界的时间曲线 |
| POST | `/tools/simulate-battle` | 输入一组玩家属性和关卡，返回胜负与用时 |
| GET | `/players?query=&page=&pageSize=` | 分页列表 |
| GET | `/players/:id` | 详情：状态、物品、功法、关卡进度、最近 50 条操作记录 |
| GET | `/operations?…&page=` | 分页查询 |
| POST | `/gm/players/:id/{grant-item,set-realm,set-cultivation,reset}` | 仅当环境变量 `ENABLE_GM_TOOLS=true` 时注册这些路由；每次调用写 `gm_*` 操作记录 |
| — | 公告、弹窗、版本更新 | 保留现有功能，迁到 `/api/v1/admin/ops/*` |

---

## 6. 客户端架构（Godot）

### 6.1 目录

```text
game/
  autoload/
    app_env.gd          环境配置：API 地址（按导出预设的特性标签选择）
    api_client.gd       所有 HTTP 请求，异步，统一错误处理
    auth_session.gd     令牌读写、登录状态、登出
    content_cache.gd    内容快照下载、校验、缓存到 user://content/<version>.json
    game_store.gd       当前玩家状态、信号 state_changed、修为插值
  scenes/
    main.tscn           只放顶栏、底栏、页面容器、弹窗层
    pages/login_page.tscn
    pages/cultivate_page.tscn
    pages/adventure_page.tscn
    pages/bag_page.tscn
    pages/skill_page.tscn
    pages/settings_page.tscn
    components/         物品格子、物品详情卡、战斗回放面板、确认弹窗、加载遮罩
  scripts/
    net/api_errors.gd   错误码 → 中文提示
    ui/…                每个页面一个脚本，单文件不超过 400 行
    update/…            保留现有热更新
  legacy/               旧本地玩法代码暂存（不进导出包），第 4 阶段结束后删除
```

### 6.2 网络层

- 用 `HTTPRequest` 节点 + `await`，禁止在主线程用 `while` 循环和 `OS.delay_msec` 等待网络。
- `ApiClient.request(method, path, body, options) -> ApiResult`，`ApiResult` 含 `ok`、`status`、`data`、`error_code`、`error_message`。
- 超时 10 秒；只对 GET 和带幂等键的 POST 自动重试 1 次（间隔 1 秒）。
- 收到 401 → 清除令牌，跳回登录页；收到 426 → 弹出强制更新；收到 503 `CONTENT_NOT_PUBLISHED` → 显示“服务器维护中”。
- 每个请求自动带 `X-Client-Version`、`Authorization`、需要时带 `Idempotency-Key`。
- API 地址：`project.godot` 里定义自定义设置 `xiuxian/network/api_base_url`，并用 Godot 的特性标签覆盖（例如 `xiuxian/network/api_base_url.staging`、`.prod`），在 `export_presets.cfg` 里为测试包、正式包分别设置特性标签。编辑器运行默认 `http://127.0.0.1:8080`。

### 6.3 状态仓库

- `GameStore.apply_state(state: Dictionary)`：整体替换，发出 `state_changed`。
- 页面只订阅 `state_changed` 和读 `GameStore`，页面之间不互相调用。
- 操作期间（请求未返回）对应按钮禁用并显示加载状态，防止重复点击。

### 6.4 修为本地插值显示

```text
显示修为 = state.cultivation
         + floor((本地估算的服务器当前时间 − lastSettledAt 秒数) / tickSeconds) × 实际每拍修为
本地估算的服务器当前时间 = state.serverTime + (本地单调时钟现在 − 收到响应时的本地单调时钟)
上限：不超过 offlineCapSeconds 对应的拍数
```

- 只用于显示；“可以突破”按钮的可用性也可按插值判断，但最终以服务器结果为准。
- 每 60 秒、应用从后台回到前台（`NOTIFICATION_APPLICATION_RESUMED`）、每次操作后，调用 `/me/sync` 校正。

### 6.5 旧代码处理

- `CultivationSession`、`SaveService`、`SaveMigrator`、`SettlementEngine`、`CombatRules.settle`、`InventoryRules`、`LongTermRules` 及洞府/门派/远行/灵兽/飞升相关 UI：第 4 阶段移入 `game/legacy/`，并在导出预设里排除该目录；页面改造完成并验收后删除。
- `CombatRules` 中的纯属性公式（`time_to_kill`、`time_to_die`、`apply_speed_to_interval`、`piece_power`）在服务器实现完成前作为对照基准保留；客户端最终不需要它们。
- `game/resources/config/*.json` 改为“初始内容种子”，移到 `backend/seeds/`，客户端不再打包。

---

## 7. 后台（admin）设计

### 7.1 菜单分组

```text
内容配置：全局配置 / 境界 / 关卡 / 掉落表 / 物品 / 功法
发布：校验与发布 / 版本历史
数值工具：成长模拟 / 战斗模拟
玩家：玩家列表（含详情）/ 操作记录
运营：公告 / 弹窗 / 客户端版本
测试工具（仅测试环境显示）：GM 工具
```

### 7.2 页面要求

- 列表：可搜索（编号、名称）、按顺序字段排序、显示“草稿相对已发布：新增 / 已修改 / 未变”标记。
- 编辑：每类内容一个专用表单组件，所有引用字段用下拉选择（数据来自草稿），枚举字段用下拉，概率字段用百分比输入（两位小数）并在保存时转换为万分比，时间字段用“小时/分钟”输入。
- 保存时后端校验单条记录（字段范围、引用存在），失败时错误显示在对应字段下方。
- “校验与发布”页：顶部是校验结果（错误红色、警告黄色，点击跳到对应记录），中间是差异列表，底部填写发布说明后点发布；有错误时发布按钮禁用。
- “版本历史”页：版本号、发布人、时间、说明；可查看全文；可“恢复到草稿”。
- “成长模拟”页：表格和折线图显示“只挂机”和“挂机 + 按推荐战力打关”两种理想玩家到达每个境界的累计时间，以及每次突破的成功率。
- 前端技术：保留 Vue 3 + Element Plus；新增 `pinia`（会话和下拉数据缓存）、`echarts`（模拟图表）；`api.ts` 只在 401 时跳登录，403 只提示“没有权限”。

---

## 8. 环境、部署与安全

### 8.1 三套环境

| 环境 | 后端 | 数据库 | 后台 | 手机包 |
|---|---|---|---|---|
| 本机开发 | `npm run dev`（127.0.0.1:8080） | `docker compose` 起的 Postgres（`xiuxian_dev` 与 `xiuxian_test` 两个库） | `vite` 代理到 127.0.0.1:8080 | Godot 编辑器直接运行 |
| 测试服 | 云服务器上 `xiuxian-api-staging` 服务 | 同机 `xiuxian_staging` 库 | `https://<域名>/admin-staging/` | 测试包（staging 特性标签），开启 GM 工具 |
| 正式服 | `xiuxian-api` 服务 | 同机 `xiuxian_prod` 库 | `https://<域名>/admin/` | 正式包（prod 特性标签），关闭 GM 工具 |

所有配置通过环境变量注入，`backend/.env.example` 列出全部变量：`NODE_ENV`、`PORT`、`DATABASE_URL`、`PUBLIC_BASE_URL`、`CORS_ORIGINS`、`ENABLE_GM_TOOLS`、`LOG_LEVEL`、`APK_BASE_URL`。启动时用 zod 校验，缺失直接退出。

### 8.2 服务器部署

- Nginx 作为入口：`api.<域名>` 反向代理到 Node 进程；`/admin/` 托管后台静态文件；Let's Encrypt 证书（certbot 自动续期）；HTTP 一律 301 到 HTTPS。
- 国内服务器绑定域名必须先完成 ICP 备案；备案完成前，测试只能继续用 IP + HTTP，但正式对外开放前必须切换到 HTTPS。
- Node 进程由 systemd 管理，崩溃自动重启；日志用 pino 输出 JSON 到 journald 或文件，配合 logrotate。
- PostgreSQL 只监听 127.0.0.1；每天 `pg_dump` 一次，保留 14 天，同步一份到阿里云 OSS；每月做一次恢复演练。
- APK 安装包放 OSS + CDN，后台只保存版本元数据和下载地址；不再由业务服务器直接传输大文件。
- 部署脚本 `tools/deploy/deploy_backend.sh`：拉取指定 git 标签 → `npm ci` → 运行测试 → 迁移数据库 → 重启服务 → 调用 `/healthz` 确认。

### 8.3 安全基线

- `@fastify/rate-limit`：登录/注册每 IP 每分钟 10 次；玩家接口每会话每秒 5 次；后台登录每 IP 每分钟 5 次。
- `@fastify/helmet`、`@fastify/cors`（只允许配置的后台域名）。
- 日志脱敏：`authorization`、`password`、`token` 字段一律打码。
- 管理员角色：`owner` 全部权限；`designer` 可编辑和发布内容、查看玩家；`viewer` 只读。GM 接口只允许 `owner`。
- 管理员登录失败 5 次锁定 15 分钟。

### 8.4 上线前合规清单（非代码事项，由项目负责人推进）

- 域名 ICP 备案。
- 用户协议与隐私政策页面，注册时必须勾选同意（接口已预留 `agreeTerms`）。
- 网络游戏实名认证与未成年人防沉迷：正式商业运营前必须接入国家新闻出版署的实名认证系统并实现时长限制；预留 `players.real_name_status` 字段，当前不实现。
- 软件著作权登记（上架国内应用商店通常需要）。
- 商业化运营需要游戏版号；未取得前只能做不收费的小范围测试。
