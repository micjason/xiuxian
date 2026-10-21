# 0.18.0 (41) 发布到 dev2（2026-10-22，北京时间）

## 合并
- `proto/release-40`（e175626 release 0.17.2 (40)，开发二号）快进进 proto/week1。
- `proto/batch5-salvage`（第五批）普通合并：be8e44b。版本号：92a1f24 release 0.18.0 (41)。

## 测试（合并后的树）
- 后端：xiuxian_test 迁移到 0050 后 `npm test` 87 个文件 / 350 个测试全过；`tsc --noEmit` 通过；后台 `npm run build` 通过。
- 客户端：Godot 4.7.2 `--import` 后 GUT 34 个脚本 / 288 个测试 / 2967 个断言全过。

## 发布
- 后端 + 后台：release 20261022-015641（发布前备份 xiuxian-dev2-20261022-015641-daily.dump、xiuxian-dev2-20261022-015712-pre-update.dump）。
  迁移 0050（when 1796000000000）已执行；内容版本仍是 3（没有发布内容，草稿里的其它改动没动）。
- 运行时读的是内容表本身（loadCurrentWorld 读草稿表），所以 0050 写进去的精粹规则 / refine_essence 物品 / bagFullSkipSources
  **不需要发布内容就生效**。后台以后再改这些数值，也同样立刻生效（和以前其它配置一样）。
- 强化经验 → 精粹：后台「现在全部换完」点了两次：第一次换 1 人（7 经验 → 5 精粹，ratio 7000，向上取整），第二次 0 人（幂等）。
  该玩家 +6 的武器还是 +6。v14check 原来 0 经验：战力 615、装备等级、精粹 0 前后一样。
- APK：http://101.132.74.32:8090/download/xiuxian-dev2-0.18.0-41.apk，sha256 52e0ab3824713fd1d696141958a08a2f10072b82ebf5441955f1fcb1b8fceb8b，
  111899293 字节，固定签名（证书 SHA-256 2A:52:56:90:57:A7:63:0D…）；latest.json 和下载回来的文件校验一致。

## 线上截图后发现并修的问题（没进 41 号包）
- 紫/橙二次确认层下面透出分解格子里的「凡品/珍品」字（格子字 z_index=1，确认层是 0）。确认层改成 z_index=10，GUT 加断言；
  修复后线上补拍 `client_preview_v180/2c_purple_confirm_fixed.png`。下一个包带上。

## 0.18.1 (42)（只发客户端，2026-10-22 02:19 北京时间）
- 249e50b 二次确认层 z_index=10（不再透出格子品质字）。
- ae213bc / 08f15e6 分解弹窗品质字：按稿放在格子下方（框顶 CELL-7，字形在两行之间），统一画在所有格子之后、不抬 z_index；
  底部渐隐 80% 处不透明，最后一行品质字被盖住，不再和「↓ 下滑查看更多」重叠；白色品质字 #8E96A3。GUT 断言字形位置 / 层次 / 渐隐不透明度。
- fdc251a release 0.18.1 (42)。后端和后台自 0.18.0 起没改，没有部署后端（服务器仍是 20261022-015641，内容版本 3）。
- APK：http://101.132.74.32:8090/download/xiuxian-dev2-0.18.1-42.apk，sha256 50318e34d6643841fcf6fd8c67382a63f3f8fa3728f5217634def66a14c074c7，111899825 字节，同一签名。
- 测试：GUT 289/289（3061 断言）；后端 350/350 + tsc。
- 截图：client_preview_v180/1c_salvage_bottom_fixed.png、2c_purple_confirm_fixed.png（线上 dev2，账号 v180shot），sheet_v180.png 已换成修复后的两张。
