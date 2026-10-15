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
