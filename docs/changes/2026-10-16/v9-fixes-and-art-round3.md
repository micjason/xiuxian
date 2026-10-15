# v9：负责人 v8 验收意见 + 美术第 3 轮（2026-10-16，分支 proto/week1，只在本地）

APK：`/workspace/builds/xiuxian-debug-v9.apk`，versionCode 29，`0.10.1-proto`，**92,856,179 字节（88.6 MiB）**（v8 是 92,660,214，多 196 KB：启动图 143 KB + 新头图等）。调试签名，v2 签名通过，`usesCleartextTraffic=true`，`api_base_url=http://10.0.2.2:8080`。截图在 `/workspace/ui_preview_v5/v9/`。

## 负责人意见逐条
1. **离线弹窗**：按钮「领取」→「知道了」，提示「点领取即可关闭」→「收益已入账」。提示不再放在卷轴里面，而是放在卷轴下面（设计稿 08 也是这样），所以下面的卷轴条不会压到它；按钮和下轴之间留了 16px 空隙。代码：`offline_popup.gd`。截图：`std_1080x1920/01_offline_popup.png`。
2. **修炼页重复信息**：顶栏已有修为条，所以删掉了莲台下面那条修为条（`home_page.gd`）；「击败怪物 ×4、掉落…」保留波次卡片里那份，删掉莲台上方的飘字。截图：`std_1080x1920/02_home.png`。
3. **战斗飘字叠成一串**：飘字按“车道”排（每边 4 条车道、左右错开），同一边同时最多 4 条，多的最旧的先收掉（`battle_page.gd`）。截图：`real/real_03_battle_ult_ready.png`。
4. **战报第一行被切一半**：让可视高度正好是整数行，零头放到底部（`battle_report.gd`），面板最小高度 250 → 340（正好 4 行）。截图：`std_1080x1920/06b_battle_auto_cast.png`。
5. **背包满提示**：改成屏幕正中的小弹窗（宽 840，标题居中，没有 ×，不盖标签栏）；其他弹层仍是底部面板（`game_popup.gd` 新增 `open_popup(title, true)`）。截图：`std_1080x1920/12_bag_full_prompt.png`、`real/real_08_bag_full_prompt.png`。
6. **屏幕适配**（1080×1920、1080×2400、1080×2400 + 顶部 90px / 底部 48px 刘海安全区）：
   - 新增开发用环境变量 `XIUXIAN_SAFE_AREA="左,上,右,下"`（画布像素）在桌面模拟刘海，正式包里没有这个变量不起作用；截图脚本 `/workspace/tools_ui/run_v9.sh <输出目录> <场景> <宽x高> [安全区]`。
   - 看到的问题并已修：**登录页**在 1080×1920 上，居中的卡片压住了「问道长生」标题下半截（`player_login.gd` 现在卡片顶不高过标题底，标题也加上顶部安全区）；弹层面板最大高度没扣刘海（`game_popup.gd` 已扣）。
   - 看到但没改的：历练页的首领详情是滚动的，1920 下「挑战」按钮要往下滑才看得到（本来就是 ScrollContainer，不是遮挡）；洞府页在 2400 上下半截只有背景图；演示数据的「演示」小标签压在头像框角上（只有演示模式有）。
   - 顶栏/标签栏在有刘海时分别下移/上移，没有遮挡；底部标签栏在 48px 手势条之上。
   - 没验证：真机上的软键盘（登录页）、真实安全区数值、横屏。截图：`std_1080x1920/`、`tall_1080x2400/`、`notch_1080x2400/`、`login2_*`。
7. **开发场景不进 APK**：`export_presets.cfg` 的 `exclude_filter` 加了 `scripts/dev/**`、`scenes/dev/**`（仓库里文件都在）。验证：v8 的 APK 里有 18 个 dev 文件，v9 里 `scripts/dev/`、`scenes/dev/`、`addons/gut/`、`tests/` 都是 0（`unzip -l` 逐项数过）。演示数据 `scripts/model/proto_mock.gd` 仍在包里（环境变量开关，没要求去掉）。
8. 无（负责人改表）。
9. **手机连后端的调研**：`/workspace/play_on_phone_options.md`（同内容在本目录 `play_on_phone_options.md`）。推荐在他自己电脑上起后端 + Postgres，手机同一 Wi-Fi，登录页填 `http://电脑局域网IP:8080`；没有起任何隧道、没有对外暴露任何东西。

## 美术第 3 轮（artist 重新交付 `/workspace/art_out/`）
并入：`bar_fill_*`×4、`bar_frame`、`chip`、`formation`（19.3 KB，在 20 KB 预算内）、`logo_title`（32.7 KB）、`panel_popup_scroll`（984×1350）、`popup_breakthrough_header`（960×420）、`ribbon_title`、`slot_*`×9、`ult_btn_cooldown`（去掉了静态弧）、新增 `splash_1080x1920`、`icons/ui_hourglass`、`android/adaptive_monochrome_432x432`、`android/main_192x192`。其余文件与之前逐字节相同。
- 校验：清单里能对上的 111 个文件，像素尺寸、体积预算、九宫格“宽高 > 2×边距”全部通过；41 个九宫格的拉伸区逐个测了（拉伸方向上的像素差 ≤6），没有变化；美术自己的 `verify_nine_result.txt` 也是 0 FAILS。
- 按负责人要求接线：
  - (a) 进度条填充在框里上下各缩进 3px（`ui_kit.gd`，bar_frame 内容边距是 0）。
  - (b) `ribbon_title` 两端平切，没有加燕尾。
  - (c) 启动图：`application/boot_splash/image=splash_1080x1920.png`，保持比例（stretch_mode=1），底色取图的边缘色 (9,12,14)，长屏上下是同色，不会有硬边；应用图标 `main_192x192`；自适应图标三层都配了（前景、背景、单色）。APK 里有 `icon_monochrome.webp` 和 `themed_icon.xml`。
  - (d) 离线弹窗用 `panel_popup_scroll`（提示放在卷轴外）；突破成功弹窗顶部用 `popup_breakthrough_header`，丝带「突破成功」压在底边；沙漏用 `ui_hourglass`；大招冷却图：进度环画在图中间暗槽里，中线半径 40px、宽 6.4px（220px 画布），按按钮大小等比放大。
  - (e) 授权：`ASSETS_LICENSES.md` 第 7 节重写，逐文件清单 `game/assets/art_delivery_license_list.csv`；AI 生成的（物品图标、背景、两张弹窗头图）标"商用条款尚未确认"；Ma Shan Zheng 是 SIL OFL 1.1（文本 `fonts/OFL-MaShanZheng.txt`）；旧 game-icons.net 图标被覆盖后只剩 15 个，仍保留 CC BY 3.0 署名；古画背景已被全部覆盖，只留历史记录；`credits.json` 同步。
- **交付里仍然不对 / 需要美术决定的**：
  1. `ribbon_title` 现在是红色卷轴缎带，只适合弹窗标题；原来页面标题（历练/背包/功法…）用的是暗色牌。我把原来的程序绘制 `ribbon_title.png` 另存为 `page_title_plate.png`（`NINE["page_title_plate"]`）继续给页面标题用。这不是美术交付的；需要美术另出暗色版页面标题牌，或确认页面标题也改红色。
  2. `ult_btn_cooldown` 的暗槽只有一圈，进度环是我画的；效果没在真机上看过。
  3. 没交付：人物/Boss 立绘（`boss_*`、`avatar*` 仍是图标风格）、`guide_*` 没有引导流程可用、`panel_popup_scroll` 之外的弹窗头图只有离线和突破两张。
  4. 仓库里还有 15 个 160×160 的旧 game-icons.net 图标（`res_bag`、`res_stone`、`ui_*` 等）不是美术交付的，清单写的是 128×128；要不要换成美术的版本由美术/负责人定。
  5. 授权：AI 生成的内容商用条款未确认；41 个剪影图标"手写 SVG"是美术自述，开发这边没独立复核。

## 验证
- 后端 vitest 69 文件 / 260 测试全过。
- GUT 172 个，171 过；唯一失败仍是 `test_main_screen_loop`（无头字体缓存报错的老噪音）。新增 `test_v9_fixes.gd`（6 个：知道了/提示位置、修炼页不重复、飘字车道、战报整行、居中弹窗、安全区覆盖）、`test_art_delivery.gd` 加 2 个（第 3 轮尺寸、启动图/四个图标/导出过滤）。
- 真实后端 e2e（本地服务 + 无头客户端）：离线弹窗、知道了确认、战斗（客户端预测与服务器一致，28.6 秒，手动大招 1 次）、突破到筑基一层、满包提示（20/20，装备没入包，提示可见）。截图在 `v9/real/`。

## 没验证
- 真机/模拟器（安装、触屏、真实刘海、启动图显示、主题图标、软键盘）。
- 截图是无头 xvfb + 演示数据，不是手机屏幕；对照设计稿是目测。
- 大招冷却环、突破头图在真机上的观感。
- 美术素材的商用授权。
