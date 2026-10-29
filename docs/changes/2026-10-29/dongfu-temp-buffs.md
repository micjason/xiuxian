# 洞府 v1 · 临时属性丹进战斗结算（开发二号）

分支：`proto/dongfu-seed-drops`（同工作树，接在种子掉落之后）  
迁移：`0048_player_active_buffs`（`when: 1795000800000`）  
未部署、未推送。

## 与洞府经营开发的约定

- **复用** `player_active_buffs`（与其 `0060_dongfu_v1` 表结构完全一致）。0048 仅 `CREATE TABLE IF NOT EXISTS` + 补 `content_items.effect` 列，**不**再插种子/草药/丹药行（合并时物品以 0060 带 `effect` 的为准；0047 占位 `ON CONFLICT DO NOTHING`）。
- 他们：`useItem` / `applyPillUse` 写 buff 行。
- 我们：读 `expires_at > now`，同 `buff_stat` 的 `buff_bp` **相加**，乘算到战斗攻防；并导出 `applyActiveBuff` 供对方直接调用。

### 表结构（双方一致）

| 列 | 类型 |
|---|---|
| id | uuid PK |
| player_id | uuid → players CASCADE |
| buff_stat | text（`attack` \| `defense`） |
| buff_bp | int（万分比，1000 = +10%） |
| started_at / expires_at | timestamptz |
| source_item_slug | text |

索引：`player_active_buffs_player_idx(player_id)`

### `applyActiveBuff`（洞府可调）

```ts
await applyActiveBuff(tx, {
  playerId,
  buffStat: "attack" | "defense",
  buffBp: 1000,
  durationSeconds: 300,
  sourceItemSlug: "pill_atk_temp",
  now,
});
```

策略：**同属性多条并存、结算相加**（不刷新、不互顶）。再吃一颗攻击丹 = 再插一行；旧行到期后自然少算。

### 物品 effect（`content_items.effect` jsonb）

```json
{ "buffStat": "attack", "buffBp": 1000, "durationSeconds": 300 }
```

修为丹（洞府处理，本分支战斗不读）：

```json
{ "cultivationGain": 100 }
```

后台「物品」页可编：临时属性 / 万分比 / 持续秒数 / 修为增益。

### 战斗接入

- `settleLocked`：算完 `statsOf` 后 `applyBuffsToStats`（攻防 × `(1 + bp/10000)`，重算战力与出手间隔）
- 挂机波次 / 自动挑战 / 手动挑战首领均走同一份 `settled.stats`
- `GET` 状态：`activeBuffs: [{ id, buffStat, buffBp, sourceItemSlug, startedAt, expiresAt, remainingSeconds }]`
- 本分支 `useItem`：仅处理带 `buffStat` 的丹；修为丹仍归洞府 `applyPillUse`

### 合并注意

1. 0048 与 0060 谁先跑都安全（IF NOT EXISTS）。
2. 物品行冲突时保留 0060 的 `effect`。
3. 双方都改了 `useItem` 时：保留洞府的 pill 分支（含修为丹），并确保会写 `player_active_buffs`；开发二号侧战斗读取即可。
