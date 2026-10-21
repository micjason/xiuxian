# 2026-10-21 批次③（服务端）：章节、每关一个首领（精英 / 章末）、首领规则、解锁链、自动挑战

分支 `proto/batch3`（基于 proto/week1 `c790eba`）。只做服务端和后台接口；后台「首领规则」页面（`BossRulesSection.vue` 整体替换）、章节页、客户端接入下一步做。

## 规则（全部可在后台改，代码里只有默认值）
- **章节** `content_chapters`：名称、顺序、战斗区背景 `bg_key`（heifeng / youming / chiyan）、章节首领特效 `boss_fx`（default | chiyan，SPEC_Q §14.7）、可选章末关 `chief_stage_slug`（空 = 本章 sort_order 最大的一关）。关卡加 `chapter_slug`。
- **首领档次**：章末关的首领 = 大首领（chief），其余关 = 小首领（精英，elite）。下发给客户端的怪物档次：normal / elite / chief。
- **首领规则** `content_globals.tuning.bossRules{elite, chief}`（配置概览「首领规则」两列）+ 单关覆盖 `bosses[0].rules`（只存改过的项）：

| 项 | 精英默认 | 章末默认 |
|---|---|---|
| 属性 | 自动 = 本关小怪 × 气血 5 / 攻 1.3 / 防 1.2（出手间隔同小怪；`statsCustom` 里列的项保留手填） | 手填 |
| 重打 / 重打奖励 / 每日次数 | 允许 / 不给 / 0 | 允许 / 给 / 5（迁移沿用原 `combat.bossDailyRewardCount`） |
| 装备品质 白/绿/蓝/紫/橙 % | 0/70/25/5/0 | 0/50/35/13/2 |
| 自动挑战 | 开，战力 ≥ 推荐 × 100%，输了 60 秒后再试 | 关 |
| 解锁下一关 | 击败本关首领 + 境界达到 | 同左 |

- **精英首通奖励**（首领 firstClear，后台可改）：灵石（炼气 50 / 筑基 150 / 金丹 450，占位数值）+ 突破石·下品 ×1 + 按品质掉率抽 1 件本境界装备。firstClear 新增 `{kind:"spiritStones", amount}`、`{kind:"gear", count}`。
- **首领装备发放**走统一接口 `grantEquipment`（ADMIN_SPEC §14，`player/grant.ts`）：source = boss_first / boss_repeat，sourceRef = 关卡编号，requestId = 战斗报告 id（玩家 + 关卡 + 进度解锁时间 + 第几次胜利）+ 序号，重放不重复发；行囊满照发、不自动分解；写 equipment_grants 流水。
- **解锁**：第一关默认解锁；后面的关 = 上一关首领已首通（规则可关）且境界达到。`/me/state.stageAccess` 每关给 unlocked / realmOk / playable / cleared / tier / chapterSlug / needs（缺什么）。挑战没解锁的关 409 `STAGE_LOCKED`，境界不够 409 `REALM_TOO_LOW`，禁止重打 409 `BOSS_REPEAT_DISABLED`。挂机关没手选时默认最后一个能进的关。
- **自动挑战**：结算（`/me/state` 心跳等）时，挂机关首领还没首通、规则允许、战力 ≥ 推荐 × 比例 → 直接打一场，结果在这次响应的 `lastSettle.autoChallenge`。每次结算最多一场；手动挑战前的结算不自动打。
- **立绘**：怪物 / 首领 `artKey`（12 个，对应 `game/assets/art/q/sprites/mon_*.png`，测试对照目录），精英没填时用本关小怪的。

## 后台接口（都要管理员）
- `GET/POST/PUT/DELETE /admin/draft/chapters[/:id]`（还有关卡的章节不能删；章末关只能选本章的关卡）
- `GET/PUT /admin/draft/boss-rules`（PUT 按列只合并传了的项；品质合计必须 100%）
- `POST /admin/draft/stages/:id/reset-boss-rule`（body `{keys?}`，不传 = 全部恢复默认）
- `GET /admin/draft/art-keys`（立绘 / 背景 / 首领特效下拉）
- 关卡接口 `PUT /admin/draft/stages/:id` 多收 `chapterSlug`、`sortOrder`、`monsters[].artKey`、`bosses[0].artKey / rules / statsCustom`；**修复**：以前保存关卡会把 sort_order 清零、next_stage_slug 清空。
- 一关只能有一只普通怪：`monsters` 传多于一只报「一关只能有一只普通怪」（游戏和客户端本来就只用第一只）。
- `next_stage_slug` 列不再读：快照里的 `nextStageSlug` 按游戏顺序（章节 → 关卡 sortOrder）现算，改顺序、新建关卡后链条自动对上（以前新建的关是 null，发布会报「必须连成一条链」）。列还在，不用迁移。

## 发布校验
每个启用关卡要有章节、恰好一个首领、怪物和首领都要有合法立绘；章节背景 / 首领特效只能选清单里的值；规则合并后品质合计 100%；旧的单首领「重复奖励橙装概率」不再接受。推荐战力「高境界不低于低境界」只在同档首领之间比。一关多于一只普通怪只给**警告**（老数据，游戏只用第一只），不拦发布。一个章节都没有的内容（老格式，只在单元测试里）不做章节检查。

## 迁移（when 从 1795000000000 起，排在 0027 之后）
- `0040_chapters`：建章节表，按关卡名「·」前的部分建 3 章并回填（赤炎火山 boss_fx = chiyan）；sort_order 是 0 的按所需境界补。
- `0041_boss_tier_art`：9 只小怪、3 个大首领回填 artKey；非章末关补精英首领；`player_stage_progress.auto_challenge_at`。
- `0042_boss_rules_defaults`：写入 bossRules 默认值（已有不动）。
- `0043_unlock_backfill`：老玩家按当前境界补齐解锁记录（以前只看境界，不会被锁）；不补精英首通。
- `0044_elite_art_backfill`：非章末关、首领还没 artKey 的，写成本关第一只普通怪的 artKey（0041 补的 6 个小首领以前只在快照里「跟随普通怪」，后台显示没配图）；客户端按精英档用 `elite_<key>` 金边图 / shader。
- 都可重复执行。本地演练：c790eba 的库 + 原型内容 + 3 个玩家 → 迁移 → 再手动重跑一遍，结果一致、发布校验 0 错误。

## 不再读取的旧配置（后台要去掉）
`combat.bossDailyRewardCount`（改读 bossRules.chief.dailyRewardLimit）、`tuning.bossOrangeChanceBp` 和单首领 `repeat.orangeChanceBp`（改读装备品质掉率）。章末重打装备品质从「按怪物权重 + 2% 橙」改成 0/50/35/13/2。
