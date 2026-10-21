# 第五批（分解 / 炼器精粹 / 满包）进度

分支 proto/batch5-salvage（基于 11be275），工作区 /workspace/xiuxian-ui-pb。不部署、不打包、不推送。

- [x] 后端（0ce4397 WIP）：精粹规则、分解产出、强化消耗、0050 迁移 + 换算记录、满包不发装备、批量分解接口；vitest 350/350（xiuxian_test_pb）、tsc 通过
- [x] 后台（WIP 提交）：EnhanceView 精粹配置 + 换算、ConfigOverview；admin build 通过
- [x] 客户端（WIP 已提交）：EnhanceModel/BagModel 精粹、SalvageModel + SalvageDialog、背包「分解」入口、详情强化消耗行、历练页满包提示条、底栏 badge_full、mock、GUT
- [x] Godot import + 全量 GUT 288/288（截图后再跑一次）
- [x] 截图 /workspace/client_preview_v18b/ + compare_sheet.png（含后台 6_*、7_*）
- [x] 变更说明 salvage-essence.md；最终全量测试后提交

## 完成（2026-10-22 01:45 UTC+8 左右）
- 最终：后端 vitest 350/350、tsc 通过、admin build 通过、Godot import + GUT 288/288（2967 断言）
- 截图：/workspace/client_preview_v18b/（1_/1b_/2_/2b_/3_/3b_/4_/5_ 客户端，6_/6b_/7_ 后台，compare_sheet.png 对照设计稿）
