# 美术交付接入（2026-10-16，分支 proto/week1，只在本地）

对应提交：`b0e1848`（美术文件 + 代码）和本次的文档/授权/版本号提交。APK：`/workspace/builds/xiuxian-debug-v8.apk`，versionCode 28，`0.10.0-proto`，**92,660,214 字节（88.4 MiB）**，v7 是 94,021,284，v8 反而小约 1.4 MB（libgodot_android.so 76 MB、classes.dex 6 MB 是大头）。

## 1. 接入了什么
- `art_out/ui`（60 个）→ `game/assets/art/ui/`：59 个 PNG + `app_icon.svg`，**同名覆盖**之前的占位。`ArtLib.NINE` 里已登记的九宫格边距没有改，交付图尺寸都满足"宽、高 > 2×边距"（`tests/unit/test_art_delivery.gd` 逐个检查）。
- `art_out/icons`（41 个）→ `assets/art/icons/`，含新增的 `tab_cave.png`（洞府标签，通过 `icon_or` 回退使用）。
- `art_out/items`（35 个）与仓库已有的逐字节相同，不用再拷。
- `art_out/bg` 10 个 webp → `assets/art/bg/`；交付清单说 `home.webp` 在 bg 里，但文件夹里没有，所以从 `/workspace/art_bg/home.webp` 补上（battle、breakthrough 与已有的相同）。
- `art_out/android` 的两张自适应图标（432×432 前景/背景）→ `assets/art/android/`，已写入 `export_presets.cfg`。1024 母版 `app_icon_1024.png` 没进仓库（留在 `/workspace/art_out/source`）。
- 代码接线（只接有现成位置的）：
  - 大招按钮 `ult_button.gd`：就绪/冷却/不可用三张图（`ult_btn_ready/cooldown/disabled`），冷却时叠一圈进度环；贴图缺失时回到原来的程序绘制。
  - 战报面板用 `battle_log_panel`（九宫格边距 40/40，内容边距 20/16），没有图时回退。
  - `ArtLib.NINE` 新增 `battle_log_panel`、`guide_bubble`、`guide_highlight`。
  - 离线头图（`has_ui` 已接）、标签栏图标、背景图自动走同名覆盖。
- 二进制处理（与之前的提交一致）：`.gitattributes` 写了 LFS 规则，但本机没装 git-lfs，所以 PNG/WEBP/SVG 和 Godot 生成的 `.import` 都是普通二进制提交（本批新增约 130 个文件）。以后在装了 git-lfs 的机器上迁移。已写进 `ASSETS_LICENSES.md` 第 7 节。
- 授权：`ASSETS_LICENSES.md` 新增第 7 节，`credits.json` 新增一组，两处一起改。美术标的授权状态是"待确认"，图标来源未核对，所以原来的 CC BY 署名保持不变。

## 2. 交付文件的问题（只报告，没有悄悄修）
尺寸：所有交付文件的像素尺寸都与 `art_slicing_checklist.csv` 一致；没有违反九宫格"宽高 > 2×边距"的文件；代码里的边距与清单一致。下面这些是其他问题：
- 体积超预算：`formation.png` 38.9 KB（预算 20 KB），`logo_title.png` 81.1 KB（预算 20 KB）。
- 九宫格拉伸区不是纯色（拉伸会出现条纹）：`chip.png`（y=158 处）、`bar_frame.png`（y=116）、`bar_fill_*.png`（x=11、y=252）、`slot_r5.png`（75/75）。边距本身没问题，是拉伸区内容有变化。
- `ult_btn_cooldown.png` 底图自带一段静态的四分之一弧，我叠的进度环会与它重叠，没在真机上判断好不好看。
- `popup_breakthrough_header.png` 与设计稿 06 的版式对不上，没有接线。
- `guide_bubble/guide_highlight/guide_hand` 已登记边距，没有引导流程，所以没用。
- `boss_*`、`avatar*` 只是图标风格的图，不是立绘。
- `app_icon.svg` 覆盖了旧的。

## 3. 仍然缺的（清单里写了、但没交付）
`panel_popup_scroll`、`ribbon_title`、`ui_hourglass`、`adaptive_monochrome`（Android 13 主题图标）、`main_192x192`、启动图（splash）、角色/Boss 立绘。

## 4. 验证
- GUT 164 个，163 过；唯一失败仍是 `test_main_screen_loop`（无头字体缓存报错的老噪音）。
- 后端 vitest 69 文件 / 260 测试全过。
- 真实后端 e2e（本地服务 + 无头客户端）：离线弹窗、战斗（客户端与服务器结果一致）、突破成功 → 筑基一层；满包提示单独重跑：背包 20/20、挑战 200、掉落装备没入包、提示可见。
- 截图：`/workspace/ui_preview_v5/v8/*.png`（17 张，Mock 场景），与 11 张设计稿的对照拼图在 `/workspace/ui_preview_v5/v8/compare/`；真实后端截图在 `/workspace/ui_preview_v5/v8/real/`。
- APK：`aapt2`/`apksigner` 检查通过，调试签名，允许明文，`api_base_url` 为 `http://10.0.2.2:8080`，自适应图标已打包。

## 5. 没有验证
- 没有在真机/模拟器上跑过（安装、触屏、安全区、图标在各启动器里的遮罩形状）。
- 截图来自无头 xvfb + Mock 场景，不是手机屏幕；对照设计稿是目测。
- 冷却大招图的叠环效果、突破头图版式未在真机上看。
- 美术素材的授权条款未确认。
