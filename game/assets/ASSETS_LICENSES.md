# 美术素材来源与授权（ASSETS_LICENSES）

> 本文件列出 `game/assets/` 里**每一项**第三方素材的名称、来源、作者、授权、修改说明和署名文字。
> 游戏内「设置 → 致谢与版本」读取同内容的 `game/assets/credits.json`（两处要一起改）。
> 生成脚本在 `tools/assets/`，可以重新生成全部程序绘制的素材。

## 先看这里：哪些要署名，哪些要上线前替换

| 类别 | 授权 | 可商用 | 需要署名 | 状态 |
|---|---|---|---|---|
| 旧图标（15 个，game-icons.net，美术第 3 轮没有覆盖的那些） | CC BY 3.0 | 可以 | **要**（见下方署名文字） | 占位 —— 上线前建议替换；不换就必须保留署名 |
| 美术交付的白色剪影图标（41 个） | 美术自述：手写 SVG 路径，原创 | 可以（美术自述，未独立核实） | 不要 | 美术已做形状相似度比对（最高 IoU 0.79），我没有重复核对 |
| 物品图标 35 张、绘制背景 13 张、弹窗头图 2 张 | **AI 生成（Grok Bot 内置图像生成）+ 代码后处理** | **商用条款尚未确认** | 未知 | **发布前必须确认**；确认不了就换成人工原创图（同名覆盖） |
| 界面框体、按钮、进度条、品质框、特效贴图、大招按钮、应用/启动图标 | 原创，代码绘制 | 可以 | 不要 | 美术第 3 轮交付，同名覆盖了此前的占位 |
| logo_title、splash_1080x1920 | 原创绘制 + Ma Shan Zheng 字形（SIL OFL 1.1） | 可以 | 随附 OFL 文本 | 字体授权已核对（见第 3 节） |
| 字体 Ma Shan Zheng、Noto Sans SC | SIL OFL 1.1 | 可以 | 随附 OFL 文本 | 正式可用；已做子集 |
| 背景画（4 幅古画裁切） | 公有领域（PD-Art） | 可以 | — | **已被美术的背景全部覆盖，仓库里不再有这些文件**，仅留作历史记录（第 2 节） |

**注意（2026-10-16 更新）：现在有“授权待确认”的素材**：AI 生成的物品图标、背景和弹窗头图（第 7 节），商用条款美术方还没有确认，**发布前必须确认**，确认不了就替换。
其余素材都可以商用；CC BY 3.0 的旧图标**必须署名**，所以 Android 版里要保留致谢页（已做）。替换方式见文末「如何替换」。

### 署名文字（CC BY 3.0，必须随游戏发布）

> Icons by Lorc, Delapouite and DarkZaitzev, from game-icons.net, licensed under CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/).

## 1. 旧图标（game-icons.net，CC BY 3.0）——现在只剩 15 个

> 2026-10-16：美术第 3 轮交付的 41 个同名白色剪影图标（手写 SVG 路径）覆盖了此前来自 game-icons.net 的 40 个图标，被覆盖的不再需要署名。下表只列**还在仓库里、没被覆盖**的 15 个，它们仍需署名，署名文字不能删。

- 来源站：https://game-icons.net/　　仓库：https://github.com/game-icons/icons（本次使用的提交 `82d948812bfe3f269ef8f731dcdb07b08160edc4`）
- 作者与主页：Lorc（http://lorcblog.blogspot.com）、Delapouite（http://delapouite.com）、DarkZaitzev（http://darkzaitzev.deviantart.com）
- 授权：Creative Commons Attribution 3.0 Unported，https://creativecommons.org/licenses/by/3.0/　　允许商用和修改，**必须署名并注明有改动**。
- 修改：原始是 512×512 的 SVG（黑底白图）。去掉黑色底板，用 cairosvg 栅格化为 160×160 白色剪影 PNG；游戏里按品质、状态在运行时染色（`modulate`）。形状没有改动。
- 生成：`tools/assets/build_icons_and_backgrounds.py`（`ICONS` 表就是下面的对应关系）。

| 文件 | game-icons 名称 | 作者 | 来源页面 |
|---|---|---|---|
| `art/icons/cat_herb.png` | mushrooms | Delapouite | https://game-icons.net/1x1/delapouite/mushrooms.html |
| `art/icons/res_bag.png` | knapsack | Lorc | https://game-icons.net/1x1/lorc/knapsack.html |
| `art/icons/res_stone.png` | crystal-shine | Lorc | https://game-icons.net/1x1/lorc/crystal-shine.html |
| `art/icons/ui_enhance.png` | upgrade | Delapouite | https://game-icons.net/1x1/delapouite/upgrade.html |
| `art/icons/ui_decompose.png` | cauldron | Lorc | https://game-icons.net/1x1/lorc/cauldron.html |
| `art/icons/ui_report.png` | tied-scroll | Lorc | https://game-icons.net/1x1/lorc/tied-scroll.html |
| `art/icons/ui_credits.png` | ringing-bell | Lorc | https://game-icons.net/1x1/lorc/ringing-bell.html |
| `art/icons/ui_sparkle.png` | sparkles | Delapouite | https://game-icons.net/1x1/delapouite/sparkles.html |
| `art/icons/ui_sun.png` | sun | Lorc | https://game-icons.net/1x1/lorc/sun.html |
| `art/icons/ui_moon.png` | moon | Lorc | https://game-icons.net/1x1/lorc/moon.html |
| `art/icons/ui_mountain.png` | mountains | Lorc | https://game-icons.net/1x1/lorc/mountains.html |
| `art/icons/ui_pagoda.png` | pagoda | Delapouite | https://game-icons.net/1x1/delapouite/pagoda.html |
| `art/icons/ui_gate.png` | heaven-gate | Delapouite | https://game-icons.net/1x1/delapouite/heaven-gate.html |
| `art/icons/ui_chest.png` | chest | Delapouite | https://game-icons.net/1x1/delapouite/chest.html |
| `art/icons/ui_crane.png` | crane | Delapouite | https://game-icons.net/1x1/delapouite/crane.html |

## 2. 背景画（公有领域的古画，维基共享资源）——历史记录，文件已被替换

> 2026-10-16：`art/bg/` 下全部背景都被美术交付的新背景覆盖（第 7 节），仓库里不再有下面这些裁切图；这一节只是记录来源。

- 授权：原作者去世超过 100 年，作品属公有领域；维基共享资源标注为 PD-Art（对平面公有领域作品的忠实翻拍同样属于公有领域）。可商用，不需要署名；游戏致谢页仍列出出处。
- 修改：裁成竖版 810×1440，整体调成偏青蓝的暗色调、降低饱和度、底部渐隐，保存为 WebP。原画文件不在仓库里（太大），下载来源见下表；加工脚本是 `tools/assets/build_icons_and_backgrounds.py`。
- 避免：没有使用带朱红大印的局部。

| 文件 | 画作 | 作者 | 来源页面（维基共享资源） |
|---|---|---|---|
| `art/bg/home.webp`、`art/bg/stage_1..6.webp` | 《千里江山图》（1113 年，北京故宫博物院） | 王希孟 | https://commons.wikimedia.org/wiki/File:Wang_Ximeng._A_Thousand_Li_of_Rivers_and_Mountains._(Complete,_51,3x1191,5_cm)._1113._Palace_museum,_Beijing.jpg |
| `art/bg/login.webp` | 《谿山行旅图》（约 1000 年，台北故宫博物院） | 范宽 | https://commons.wikimedia.org/wiki/File:Fan_Kuan_-_Travelers_Among_Mountains_and_Streams_-_Google_Art_Project.jpg |
| `art/bg/character.webp`、`art/bg/bag.webp` | 《早春图》（1072 年，台北故宫博物院） | 郭熙 | https://commons.wikimedia.org/wiki/File:Guo_Xi_-_Early_Spring_(large).jpg |
| `art/bg/skill.webp` | 《玉洞仙源图》（明代，北京故宫博物院） | 仇英 | https://commons.wikimedia.org/wiki/File:Jade_Cave_Fairy_Land_-_Qiu_Ying.jpg 。**注意**：前三幅的文件已按文件大小和像素核对过；这一幅下载的是 800 像素宽的版本，和共享资源上列出的几个版本（`Jade_Cave_Fairy_Land_-_Qiu_Ying.jpg`、`Qiu_Ying_Jade_Cave_Fairy_Land.jpg`、`仇英玉洞仙源图轴.png`）的像素不完全一致，没能确认是哪一个。画作本身是公有领域，不影响授权；正式上线前要换成原创插画，届时一并处理。 |

## 3. 字体（SIL Open Font License 1.1）

| 文件 | 字体 | 作者 | 来源 | 授权文本 | 修改 |
|---|---|---|---|---|---|
| `fonts/MaShanZheng-Regular.subset.woff2` | Ma Shan Zheng（马善政毛笔楷书） | The Ma Shan Zheng Project Authors | https://fonts.google.com/specimen/Ma+Shan+Zheng ；https://github.com/googlefonts/mashanzheng | `fonts/OFL-MaShanZheng.txt` | 只保留 GB2312 一级汉字和游戏里用到的字（fontTools `pyftsubset`），转 WOFF2 |
| `fonts/NotoSansSC-Regular.subset.woff2` | Noto Sans SC | Google / Adobe（Source Han Sans） | https://fonts.google.com/noto/specimen/Noto+Sans+SC ；https://github.com/notofonts/noto-cjk | `fonts/OFL-NotoSansSC.txt` | 同上：子集 + WOFF2。字体里没有的字（子集外的生僻字）自动退回系统字体 |

OFL 允许商用、嵌入游戏、修改和再发布，不得单独出售字体本身；修改版不能使用保留字体名 “Source”（本项目的文件名里没有用）。

## 4. 程序绘制的素材（没有第三方素材）

这些最初全部由 `tools/assets/build_ui_frames.py` 画出来（2026-10-16 起其中一部分被美术第 3 轮的同名图覆盖，见第 7 节；`page_title_plate.png` 就是原来的 `ribbon_title.png` 另存，页面标题牌继续用它）（PIL，超采样抗锯齿），**没有使用任何外部图片**，版权属于本项目。
正式美术出图后，同名文件覆盖即可，九宫格边距在 `scripts/ui/art/art_lib.gd` 的 `NINE` 表里。

- `art/ui/btn_*`（主要/次要/玉色/危险/幽灵按钮的常态、按下、禁用）、`panel_*`、`ribbon_title`、`chip`、`toast`、`row_*`
- `art/ui/slot_*`（物品格：空、锁定、选中、六档品质框）、`bar_*`（进度条框与四色填充）、`reddot`、`divider`、`dock_bg`、`tab_selected_bg`
- `art/ui/formation`（阵法）、`mist`（可平铺云雾噪声，FFT 噪声生成）、`glow_soft`、`fade_*`、`topbar_fade`
- `art/ui/logo_title`（用 Ma Shan Zheng 烘焙的标题字，OFL 允许）

## 5. 仓库里原有的文件

- `art/ui/app_icon.svg`（应用图标）是仓库原有文件，不是本轮添加的，来源和授权需要项目方自己确认。
- `assets/images/*.png` 是仓库原有的旧图（Git LFS 指针文件，本轮的界面已不再使用）。

## 6. 没有用到、但下载过的素材

- ZCOOL XiaoWei（OFL）只在评估时下载，**没有**放进仓库。
- game-icons.net 里其他图标没有用，也不在仓库里。

## 7. 美术交付（2026-10-16，美术同事交付的切图，已并入）

来源说明照抄美术提供的 `ASSETS_LICENSES_art_entry.md` 和 `delivery_license_list.csv`（逐文件清单：`art_delivery_license_list.csv`，155 行）。**原则：不确定的一律是“待确认”，没有写成“已确认”。**

| 类别 | 文件 | 制作方式（美术自述） | 授权状态 | 要做的事 |
|---|---|---|---|---|
| A. AI 生成 + 代码后处理 | `art/items/*.png`（35）；绘制背景 `art/bg/home、battle、breakthrough`（来自 /workspace/art_bg）及其衍生裁切 | Grok Bot 内置图像生成按文字描述出图，再抠透明底、缩放、调色板压缩 | **商用条款尚未确认** | 发布前确认提供方的商用/再授权条款并留存生成记录（日期、提示词）；确认不了就用人工原创图替换同名文件 |
| B. 原创，代码绘制 | `art/ui/` 下的九宫格、按钮、框体、进度条、品质框、格子框、特效/渐隐/雾/阵法贴图、大招按钮、引导件、红点、`ribbon_title`、`panel_popup_scroll`；`art/icons/*.png` 白色剪影（41，含 `ui_hourglass`）；`art/ui/app_icon.svg`；`art/android/` 4 张（自适应前景/背景/单色、`main_192x192`）；`art/bg/` 另外 10 张过渡背景（程序绘制） | Pillow / numpy / cairosvg / 无头 Chrome，路径和形状手写 | 原创，无第三方素材，可商用 | 无 |
| B+C. 原创 + OFL 字体 | `art/ui/logo_title.png`、`art/ui/splash_1080x1920.png` | 字形来自 Ma Shan Zheng，其余代码绘制 | 可商用；字体为 SIL OFL 1.1 | 致谢页/本文件列出字体和 OFL 1.1 文本（`fonts/OFL-MaShanZheng.txt`） |
| D. 由 AI 合成图衍生 | `art/ui/popup_offline_header.png`、`art/ui/popup_breakthrough_header.png` | 人物主体取自 AI 生成的界面图再裁切，加光晕、闪电、星光、雾 | **同 A：商用条款尚未确认** | 同 A；A 类被替换时这两张的人物也要换 |

备注：
- **图标来源**：美术说明 41 张白色剪影图标全是手写 SVG 路径，没有取自 game-icons.net，并做了形状相似度比对（4239 个 SVG，最高 IoU 0.79，没有 ≥0.85 的描摹迹象）。这是美术的自述，开发这边没有独立复核。所以这 41 张不需要 CC BY 署名；**没被覆盖的 15 个旧图标仍要署名**（第 1 节）。
- **Ma Shan Zheng**：字体文件内嵌的版权与授权信息写的是 SIL OFL 1.1（Copyright 2018 The MaShanZheng Project Authors），完整文本在 `fonts/OFL-MaShanZheng.txt`；可商用、可嵌入，不得单独出售字体。
- **美术自己写明没核实的**：第一批生成器 `make.py` 已丢失，第一批 B 类文件是否“程序绘制”依据交付记录判断，没有逐个反推。
- `art/ui/page_title_plate.png` 不是美术交付的：它是原来的 `ribbon_title.png`（本项目程序绘制的占位）另存，因为美术第 3 轮把 `ribbon_title` 交成了红色卷轴缎带，只适合弹窗标题；页面标题牌需要美术另出暗色版。
- 二进制文件（png/webp/svg）按仓库既有做法直接提交；`.gitattributes` 里写了 LFS 过滤规则，但本机没装 git-lfs，所以这些文件和之前的美术一样是普通二进制提交（以后在装了 git-lfs 的机器上迁移）。

## 如何替换

1. 同名文件覆盖 `game/assets/art/...`；尺寸可以不同，九宫格边距改 `art_lib.gd` 里的 `NINE`。
2. 物品图标：把 `<物品 slug>.png` 放到 `game/assets/art/items/`，物品格会自动显示原图（不染色）。
3. 换完后在 Godot 里重新导出主题：`godot --headless --path game --script res://scripts/dev/export_theme.gd`。
4. 更新本文件和 `credits.json`；全部换成自有素材后，可以把致谢页里的 CC BY 署名删掉。
