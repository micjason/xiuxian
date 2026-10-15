#!/usr/bin/env bash
# 重新生成全部数值报告（在仓库根目录运行）。
set -euo pipefail
cd "$(dirname "$0")/../../backend"
OUT=${OUT:-/workspace}
FACTOR=${FACTOR:-0.3}
# 1) 第 1 周：设计表 v1.1 对照（装备速度比例 1 = 旧生成器，保留作基线）
npx tsx ../tools/sim/sim.ts --out "$OUT/sim_report_week1.md"
# 2) 第 1b 周：调参（扫描 + 重推首领 + 回填表 3.1 + 修为需求提案）。默认 0.3；历史报告是 0.1 时的结果
npx tsx ../tools/sim/sim.ts --tune --factor "$FACTOR" --out /tmp/sim_unused.md --tune-out /tmp/sim_tuning.md --derive-out /tmp/prototype-derived.config.json
npx tsx ../tools/sim/sim.ts --config /tmp/prototype-derived.config.json --out /tmp/sim_verify.md
{ cat /tmp/sim_tuning.md; printf '\n---\n\n'; cat /tmp/sim_verify.md; } > "$OUT/sim_report_week1b.md"
# 3) 第 2 周：设计表 v1.2 逐项复核（生成器 factor 0.3，v1.2 的数字）
npx tsx ../tools/sim/sim.ts --config ../tools/sim/prototype-v1.2.config.json --out "$OUT/sim_report_week2.md"
echo "reports in $OUT"
