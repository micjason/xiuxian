# 药园分配 v1（可玩）

分支：`cursor/garden-allocation-v1-713f`  
迁移：`0061_garden_allocation`（journal `when: 1800100000000`，≥ 1799100000000，晚于 0060）  
设计：`docs/superpowers/specs/2026-10-29-garden-allocation-v1-design.md`

## 玩家能做什么

- 洞府总览加减灵仆，分到药园或炼丹。闲置没有加成。
- 分配改的是时间：每名灵仆缩短成熟 / 炼制时间，不增加产量。改分配时按已完成比例重算剩余时间。
- 花灵木升级药园（地块 +1）或炼丹（队列 +1）。灵石消耗按升级表，出厂前几档为 0。
- 原来的种植、领取、炼丹、强化入口不变。

## 出厂默认（`globals.dongfu`，后台「游戏配置 → 洞府」可改）

| 项 | 值 |
|---|---|
| 初始灵仆 | 4 |
| 初始灵木 | 32（第一次打开洞府发一次，物品 `wood_lingmu`） |
| 每仆缩短 | 药园 5%，炼丹 5% |
| 最短时长 | 原时长的 20% |
| 药园升级 | 2 级 8 灵木 +1 地块；3 级 16 灵木 +1；4 级 32 灵木 + 20 灵石 +1 |
| 炼丹升级 | 2 级 8 灵木 +1 队列；3 级 16 灵木 +1。队列上限 4 |
| 关卡掉落 | 若 `tuning.seedDrops` 还没有灵木，追加 6%（600 万分比）×1 |

1 级地块仍是 4，1 级炼丹队列仍是 2。4 名灵仆全分到一边时，时长变为原来的 80%（60 秒种子约 48 秒）。

## 接口

- `POST /api/v1/me/dongfu/allocate` `{ garden, alchemy }`
- `POST /api/v1/me/dongfu/upgrade` `{ facility: "garden" | "alchemy" }`
- `state.dongfu` 增加 `allocation`、`servantTotal`、`gardenLevel`、`alchemyLevel`、`timeScale`、`upgrades`、`woodCount`

本轮不部署。
