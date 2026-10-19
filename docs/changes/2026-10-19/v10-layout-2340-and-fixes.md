# v10：1080×2340 画布、标签栏贴底、历练页空状态、后台左侧固定和弹窗点蒙层关闭（2026-10-19）

来源：Chengpeng 在 Mac 的 Godot 编辑器里跑第一版后的反馈（负责人转述）。全部在 `proto/week1` 本地提交，没有推送。

## 原因与改动

### B 标签栏没在最底部、遮住内容
- **原因（最可能）**：`UiSafeArea.current()` 在桌面上也读了 `DisplayServer.get_display_safe_area()`。桌面上这个值是“整块屏幕扣掉菜单栏 / Dock / 刘海”，以屏幕为基准，和游戏窗口无关；代码把它当手机的手势条，换算成画布像素（单边最多 240）后，把标签栏整体往上顶、内容区也跟着缩，窗口最下面就多出一截空白。
- **验证情况**：盒子上是无头 Linux，没法复现 Mac 的真实数值。我用 Mac 风格的数值（菜单栏 76、Dock 140）写了测试，证明这套算法会得到 140 的底部空白；用 `XIUXIAN_SAFE_AREA` 调试变量也能得到同样的现象。没有在 Mac 上亲眼确认。
- **改动**：只在 Android / iOS 上读系统安全区，桌面和编辑器一律 0（`UiSafeArea.platform_has_safe_area()`、`UiSafeArea.resolve()`）。调试构建启动时会在输出面板打印一行 `[layout] 视口 … 窗口 … 安全区 …`，如果 Mac 上还有问题，把这一行发回来就能定位。
- 标签栏：整块（标签栏 + 48 像素同色填充）贴屏幕最底边；填充高度取 max(48, 系统手势条)。页面内容区下沿 = 标签栏上沿 − 16，各页在这个区域里自己滚动。
- 画布：`project.godot` 视口 1080×2340，窗口 540×1170，`canvas_items + keep_width`（宽度恒为 1080，高度随屏幕：16:9 是 1920，2340 基准，20:9 以上更高）。代码里不再写死 1920（`UiTokens.BASE_SIZE`）。

### C 历练页「黑风岭一、二」下面写“这个境界还没有可以打的关卡”
- **原因**：不是数据错，是文案和展示的问题。上面列的“黑风岭·一 / 二”是“挂机刷怪地点”（普通关卡，只有小怪）；下面的关卡列表只列有首领的关卡。原型数据里首领只在每个大境界的第三层（黑风岭·三 = 炼气三层、幽冥古道·三 = 筑基三层、赤炎火山·三 = 金丹三层），所以炼气一层、二层没有首领关，列表是空的，但文案写成“没有关卡”，和上面的刷怪地点互相矛盾。其他境界检查结果：只有炼气一层、二层如此，其余境界都有首领关。
- **改动**：历练页列出当前境界已解锁的全部关卡（有首领的可挑战，没首领的只显示“怪物：xx · 无首领”），再加一张灰色锁定卡写明“首领：黑风熊王 · 炼气三层解锁”；选中没有首领的关卡时，详情卡显示怪物数据、掉落概率和一句说明，没有挑战按钮。旧文案删除。
- 首领详情的掉落改为读服务器真实字段（repeat 里的装备 / 额外物品和概率、firstClear 首通奖励），不再显示“没有掉落”。
- 换境界（突破后）自动重新选默认关卡；心跳刷新时保持滚动位置。
- 要不要给炼气一、二层加首领，是策划问题，没有改数值。

### D 后台
- 左侧菜单固定、只有右侧内容区滚动：外壳 `height: 100vh; overflow: hidden`，`.app-main` 自己滚动（改前整页滚，左边跟着滚走了 600 像素）。
- 所有弹窗 / 抽屉点蒙层关闭：Element Plus 的 el-dialog / el-drawer 默认就能关；唯一显式关掉的是 `EditDrawer`（右侧编辑抽屉，`:close-on-click-modal="false"`），改为 true，原有的 `before-close` 会在有未保存改动时先弹“放弃未保存的改动？”确认，没改动就直接关。新增 `src/overlayDefaults.ts` 在 `main.ts` 里把 ElDialog / ElDrawer 的默认值统一设为 true，防止以后再有人单独关掉；`confirm.ts` 的确认框和危险操作输入框也统一 `closeOnClickModal: true`。
- 检查过的弹窗 / 抽屉：全局搜索（el-dialog）、EditDrawer（所有配置页的右侧编辑抽屉）、玩家详情抽屉（PlayersView）、版本改动弹窗（VersionsView）、战力 / 战斗模拟 / 战斗结果三个弹窗（SimPanel）、试打弹窗（TrialDialog）、确认框 / 危险确认框（confirm.ts）。

## 文件
- game：`project.godot`、`scripts/ui/ui_safe_area.gd`、`ui_tokens.gd`、`main_theme.gd`、`player_login.gd`、`play_screen.gd`、`shell/tab_bar_view.gd`、`pages/stage_page.gd`、`scripts/model/proto_mock.gd`（演示数据新增 `realm:<slug>` 场景）、`scripts/dev/capture_sizes.gd`（按窗口尺寸截图）、`tests/unit/test_v10_layout.gd`（8 个新测试）。
- admin：`src/layouts/AdminLayout.vue`、`src/components/EditDrawer.vue`、`src/composables/confirm.ts`、`src/overlayDefaults.ts`、`src/main.ts`。

## 验证
- GUT：181/181 通过（含 8 个新测试）。后端 vitest 260 / 260 通过（后端没改）。后台 lint、vue-tsc、build 通过。
- 截图 `/workspace/ui_preview_v10/`：1080×2340、540×1170、1080×2520、540×960、1080×1920、1125×2436 窗口下的 5 个主页面；后台截图在 `admin/`。
- 没验证：Mac 编辑器里的真实窗口、真机。截图是无头 xvfb + 演示数据。
