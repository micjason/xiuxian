# 洞府 v1 · 关卡种子掉落（开发二号草稿）

分支：`proto/dongfu-seed-drops`（工作树 `/workspace/xiuxian-ui-df-seed`，基于 `proto/week1` @ `152e182`）  
迁移：`0047_dongfu_seed_drops`（`when: 1795000700000`，插在 0046 与 0050 之间；避开 lead 的 0053–0059 与洞府经营的 0060–0069）  
未部署、未推送。

## 给洞府经营开发的接口形状（可直接对接）

### 全局默认（配置概览 → tuning.seedDrops）

`GET/PUT /admin/draft/config-overview` 的 `tuning.seedDrops`：

```json
{
  "seedDrops": [
    { "itemSlug": "seed_lingcao", "chanceBp": 800, "minCount": 1, "maxCount": 1 },
    { "itemSlug": "seed_qingxin", "chanceBp": 400, "minCount": 1, "maxCount": 1 }
  ]
}
```

- `itemSlug` = `content_items.slug`（后台表单里的 `itemId` 也是同一个 slug）
- `chanceBp`：万分比（800 = 8%）；每只普通怪击杀独立掷一次
- `minCount` / `maxCount`：命中时发的件数（含端点）

### 单关覆盖（content_stages.seed_drops）

`PUT /admin/draft/stages/:id` 可带：

```json
{
  "seedDrops": null
}
```

| 值 | 含义 |
|---|---|
| `null` / 不传（创建时默认 null） | 跟随全局 `tuning.seedDrops` |
| `[]` | 本关明确不掉种子 |
| `[{ itemId, chancePercent, minCount, maxCount }, ...]` | 本关覆盖（`itemId` = slug；也接受 `itemSlug` + `chanceBp`） |

### 快照 / 运行时（客户端与洞府读这个）

`loadDraftSnapshot` / 当前内容里每一关：

```ts
stage.seedDrops          // 已合并的生效表 SeedDropEntry[]
stage.seedDropsOverride  // 库里的覆盖原样：null | SeedDropEntry[]
globals.tuning.seedDrops // 全局默认
```

### 发放路径

- 在线：`settleWaves` 每只击杀后掷种子，经 `grantItem` → `addStack`（可堆叠材料，满包也照发）
- 离线：`settleOfflineSeedDrops` 按波次节奏估算击杀数，只发种子（装备仍仅在线）
- `source` = `stage_drop` / 行囊 source 字符串 `wave:{stageSlug}`
- 与突破石一样：**堆叠材料目前没有 equipment_grants 式 requestId 幂等**；同一结算不会重复调用。若洞府领取也要幂等，另开领取单号。

### 物品编号（迁移 0047 已写入，ON CONFLICT DO NOTHING）

| slug | kind | 说明 |
|---|---|---|
| `seed_lingcao` | material | 灵草种子 |
| `seed_qingxin` | material | 清心草种子 |
| `herb_lingcao` | material | 灵草 |
| `herb_qingxin` | material | 清心草 |
| `pill_cultivate` | pill | 修为丹（洞府 useItem） |
| `pill_atk_temp` | pill | 攻击临时丹 |
| `pill_def_temp` | pill | 防御临时丹 |

约定：`seed_<key>` / `herb_<key>`，`stackable: true`。

## 临时属性丹（未实现，挂钩点备忘）

洞府经营开发提议的效果形状：

```ts
{ buffStat: "attack" | "defense", buffBp: number, durationSeconds: number }
```

建议挂在配方或 `content_items` 扩展字段上。战斗结算挂钩点（开发二号后续）：

- 在线/首领：`backend/src/modules/loop/actions.ts` 里进战斗前的 `statsOf(...)` / `grantBossRewards` 之前，把玩家身上未过期的临时丹加成合并进 `stats`
- 挂机波次：`settleWaves` 使用的 `input.stats` 同一来源
- 不要改境界表上的「大招」字段；技能仍走功法学习

开发二号本分支**只做种子掉落**，丹药使用与 buff 结算留给后续提交。

## 后台

- 配置概览新卡片「种子掉落」（`SeedDropsSection.vue`）
- 关卡抽屉「种子掉落」（`StageSeedDrops.vue`）：跟随全局 / 本关自定义 / 清空=本关不掉

## 冲突规避

未改：分解/强化、洞府页、`main.tscn`、设置弹窗。对共享面的改动仅限 `tuning` 增字段、`content_stages.seed_drops` 新列、snapshot/ops-content/waves/actions 最小接线。
