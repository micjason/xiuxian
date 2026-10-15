# tools/sim — 数值模拟

按配置推演：参考角色每关的击杀速度、首领战（含手动/自动大招）、到达各境界层的时间，输出 Markdown 对照表并标出和设计表不一致的地方。

```bash
cd backend
npx tsx ../tools/sim/sim.ts                       # 默认配置 + 输出 /workspace/sim_report_week1.md
npx tsx ../tools/sim/sim.ts --config ../tools/sim/prototype-v1.1.config.json --out /tmp/report.md
```

- 配置 `prototype-v1.1.config.json` = 设计表 v1.1 的数字（境界、怪物、首领、装备、大招、引导脚本、表里的结论）。改数字重跑即可。
- 复用后端代码：`simulateBattle`、`computePower`、`gearBudgetOf/splitGearBudget`（装备生成器）、`enhancedStat`、`settleTicks`。
- 大招后端还没有，脚本里按设计表 2.4 实现（`simulateBoss`）；无大招时与后端 `simulateBattle` 逐项自检一致。
- 不连数据库、不读线上内容，没有随机。结论的边界见报告第 6 节。

## 调参模式与 v1.2 复核

```bash
# 调参：扫描装备速度比例、按目标（首领 25–35 秒、剩血 30–35%、不贴 0.5 秒下限）重推首领血量，
# 回填表 3.1，并给出各层修为需求提案（日程 A 走完 9 层约 2.2 天）
npx tsx ../tools/sim/sim.ts --tune --factor 0.3 --out /tmp/x.md --tune-out /tmp/tuning.md --derive-out /tmp/derived.json
# v1.2 逐项复核（报告第 7 节：每个“待开发第 2 周模拟复核”的数，差 >5% 标 ⚠️）
npx tsx ../tools/sim/sim.ts --config ../tools/sim/prototype-v1.2.config.json --out /tmp/week2.md
# 全部重跑（默认装备速度比例 0.3）：tools/sim/run_all.sh
```

- 可选参数：`--factor`（装备速度比例）、`--boss-seconds`、`--boss-remain`、`--days-a`、`--tune-out`、`--derive-out`。
- 装备速度比例对应后台 `combat.gearSpeedFactor`（默认 0.3）。比例 1 = 旧生成器（第 1 周基线）。
- `prototype-v1.2.config.json` = 设计表 v1.2 的数字；`sim_report_week1b.md` 是 factor 0.1 的历史调参，现行结论以 week2 报告为准。
