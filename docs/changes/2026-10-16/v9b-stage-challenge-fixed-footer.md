# v9b：历练页「挑战」按钮固定在底部

APK：`/workspace/builds/xiuxian-debug-v9b.apk`（92,856,491 字节，versionCode 30，`0.10.1-proto`）。截图：`/workspace/ui_preview_v5/v9b/`。

## 改了什么
- `game/scripts/ui/pages/stage_page.gd`：「挑战 <首领>」按钮从滚动区的首领详情卡里挪出来，放进页面底部的固定栏 `ChallengeBar`（`StagePage` 的最后一个子节点，在 `ScrollContainer` 下面）。详情内容在它上面滚动。
- 页面容器 `_page_host` 本来就停在标签栏 + 安全区 + 间距的上方，所以按钮不会盖住标签栏，刘海/手势条的底部安全区也自动避开。
- “我的战力低于推荐值”提示仍在详情卡里（不占固定栏高度）。
- 按钮的 `challenge_requested` 信号、忙碌 / 无首领时置灰的行为不变；新增 `StagePage.challenge_button()` 供测试。
- 没选中关卡或没有可展示首领时固定栏隐藏。
- `export_presets.cfg`：versionCode 29 → 30，只为了能直接覆盖安装 v9。
- 没有加洞府占位文字（负责人说先不处理）。

## 测试
- `test_v9_fixes.gd` 新增：按钮不在滚动区内、下沿不低于标签栏上沿、在滚动区下面、高度 ≥ 96。
- GUT 173 个，172 过（`test_main_screen_loop` 老噪音失败）。
- 真实后端 e2e（本地 :8787，`xiuxian_e2e`）：注册、战斗、离线弹窗、突破门槛通过。

## 截图（修改前后）
`before_1080x1920 / after_1080x1920`、`before_1080x2400 / after_1080x2400`、`before_notch_1080x2400 / after_notch_1080x2400`，对比图 `compare_before_after.png`。修改前 1920 高屏要滚到最下面才看见按钮，2400 高屏提示被标签栏压住。

## 没验证
真机上的滑动手感与真实刘海。
