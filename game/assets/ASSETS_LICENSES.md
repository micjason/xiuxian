# 美术素材来源与授权（ASSETS_LICENSES）

> 本文件列出 `game/assets/` 里**每一项**第三方素材的名称、来源、作者、授权、修改说明和署名文字。
> 游戏内「设置 → 致谢与版本」读取同内容的 `game/assets/credits.json`（两处要一起改）。
> 生成脚本在 `tools/assets/`，可以重新生成全部程序绘制的素材。

## 先看这里：哪些要署名，哪些要上线前替换

| 类别 | 授权 | 可商用 | 需要署名 | 状态 |
|---|---|---|---|---|
| 图标（55 个，game-icons.net） | CC BY 3.0 | 可以 | **要**（见下方署名文字） | 占位 —— 上线前建议替换为正式图标；不换就必须保留署名 |
| 背景画（4 幅古画裁切调色） | 公有领域（PD-Art） | 可以 | 不要（但建议标注出处） | 占位 —— 正式版建议换成原创插画 |
| 字体 Ma Shan Zheng、Noto Sans SC | SIL OFL 1.1 | 可以 | 随附 OFL 文本 | 正式可用；已做子集 |
| 框体、面板、按钮、进度条、红点、云雾、阵法、Logo、应用图标 | 程序绘制，无第三方素材 | 可以 | 不要 | 占位 —— 美术出图后同名文件覆盖即可 |

**当前没有任何“仅限非商用”或“授权不明”的素材。** 客户放宽授权后，本轮也没有引入这类素材：所有素材都可以商用，
但 CC BY 3.0 的图标**必须署名**，所以在 Android 版里要保留致谢页（已做）。整套美术都是**占位，上线前由正式美术替换**；
替换方式见文末「如何替换」。

### 署名文字（CC BY 3.0，必须随游戏发布）

> Icons by Lorc, Delapouite and DarkZaitzev, from game-icons.net, licensed under CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/).

## 1. 图标（game-icons.net，CC BY 3.0）

- 来源站：https://game-icons.net/　　仓库：https://github.com/game-icons/icons（本次使用的提交 `82d948812bfe3f269ef8f731dcdb07b08160edc4`）
- 作者与主页：Lorc（http://lorcblog.blogspot.com）、Delapouite（http://delapouite.com）、DarkZaitzev（http://darkzaitzev.deviantart.com）
- 授权：Creative Commons Attribution 3.0 Unported，https://creativecommons.org/licenses/by/3.0/　　允许商用和修改，**必须署名并注明有改动**。
- 修改：原始是 512×512 的 SVG（黑底白图）。去掉黑色底板，用 cairosvg 栅格化为 160×160 白色剪影 PNG；游戏里按品质、状态在运行时染色（`modulate`）。形状没有改动。
- 生成：`tools/assets/build_icons_and_backgrounds.py`（`ICONS` 表就是下面的对应关系）。

| 文件 | game-icons 名称 | 作者 | 来源页面 |
|---|---|---|---|
| `art/icons/slot_weapon.png` | broadsword | Lorc | https://game-icons.net/1x1/lorc/broadsword.html |
| `art/icons/slot_helmet.png` | jewel-crown | Delapouite | https://game-icons.net/1x1/delapouite/jewel-crown.html |
| `art/icons/slot_clothes.png` | robe | Lorc | https://game-icons.net/1x1/lorc/robe.html |
| `art/icons/slot_gloves.png` | bracer | Delapouite | https://game-icons.net/1x1/delapouite/bracer.html |
| `art/icons/slot_shoes.png` | tabi-boot | DarkZaitzev | https://game-icons.net/1x1/darkzaitzev/tabi-boot.html |
| `art/icons/slot_accessory.png` | gem-pendant | Lorc | https://game-icons.net/1x1/lorc/gem-pendant.html |
| `art/icons/slot_artifact.png` | dragon-orb | Delapouite | https://game-icons.net/1x1/delapouite/dragon-orb.html |
| `art/icons/slot_pet.png` | fox-head | Lorc | https://game-icons.net/1x1/lorc/fox-head.html |
| `art/icons/cat_equipment.png` | broadsword | Lorc | https://game-icons.net/1x1/lorc/broadsword.html |
| `art/icons/cat_material.png` | crystal-cluster | Lorc | https://game-icons.net/1x1/lorc/crystal-cluster.html |
| `art/icons/cat_pill.png` | pill | Lorc | https://game-icons.net/1x1/lorc/pill.html |
| `art/icons/cat_book.png` | spell-book | Delapouite | https://game-icons.net/1x1/delapouite/spell-book.html |
| `art/icons/cat_scroll.png` | scroll-unfurled | Lorc | https://game-icons.net/1x1/lorc/scroll-unfurled.html |
| `art/icons/cat_herb.png` | mushrooms | Delapouite | https://game-icons.net/1x1/delapouite/mushrooms.html |
| `art/icons/cat_other.png` | gems | Lorc | https://game-icons.net/1x1/lorc/gems.html |
| `art/icons/tab_cultivate.png` | lotus | Lorc | https://game-icons.net/1x1/lorc/lotus.html |
| `art/icons/tab_adventure.png` | crossed-swords | Lorc | https://game-icons.net/1x1/lorc/crossed-swords.html |
| `art/icons/tab_character.png` | beams-aura | Lorc | https://game-icons.net/1x1/lorc/beams-aura.html |
| `art/icons/tab_bag.png` | knapsack | Lorc | https://game-icons.net/1x1/lorc/knapsack.html |
| `art/icons/tab_skill.png` | secret-book | Delapouite | https://game-icons.net/1x1/delapouite/secret-book.html |
| `art/icons/res_cultivation.png` | magic-swirl | Lorc | https://game-icons.net/1x1/lorc/magic-swirl.html |
| `art/icons/res_power.png` | muscle-up | Lorc | https://game-icons.net/1x1/lorc/muscle-up.html |
| `art/icons/res_enhance.png` | anvil | Lorc | https://game-icons.net/1x1/lorc/anvil.html |
| `art/icons/res_bag.png` | knapsack | Lorc | https://game-icons.net/1x1/lorc/knapsack.html |
| `art/icons/res_stone.png` | crystal-shine | Lorc | https://game-icons.net/1x1/lorc/crystal-shine.html |
| `art/icons/ui_enhance.png` | upgrade | Delapouite | https://game-icons.net/1x1/delapouite/upgrade.html |
| `art/icons/ui_decompose.png` | cauldron | Lorc | https://game-icons.net/1x1/lorc/cauldron.html |
| `art/icons/ui_lock.png` | padlock | Lorc | https://game-icons.net/1x1/lorc/padlock.html |
| `art/icons/ui_settings.png` | cog | Lorc | https://game-icons.net/1x1/lorc/cog.html |
| `art/icons/ui_report.png` | tied-scroll | Lorc | https://game-icons.net/1x1/lorc/tied-scroll.html |
| `art/icons/ui_credits.png` | ringing-bell | Lorc | https://game-icons.net/1x1/lorc/ringing-bell.html |
| `art/icons/ui_sparkle.png` | sparkles | Delapouite | https://game-icons.net/1x1/delapouite/sparkles.html |
| `art/icons/ui_yinyang.png` | yin-yang | Delapouite | https://game-icons.net/1x1/delapouite/yin-yang.html |
| `art/icons/ui_sun.png` | sun | Lorc | https://game-icons.net/1x1/lorc/sun.html |
| `art/icons/ui_moon.png` | moon | Lorc | https://game-icons.net/1x1/lorc/moon.html |
| `art/icons/ui_mountain.png` | mountains | Lorc | https://game-icons.net/1x1/lorc/mountains.html |
| `art/icons/ui_pagoda.png` | pagoda | Delapouite | https://game-icons.net/1x1/delapouite/pagoda.html |
| `art/icons/ui_gate.png` | heaven-gate | Delapouite | https://game-icons.net/1x1/delapouite/heaven-gate.html |
| `art/icons/ui_chest.png` | chest | Delapouite | https://game-icons.net/1x1/delapouite/chest.html |
| `art/icons/ui_crane.png` | crane | Delapouite | https://game-icons.net/1x1/delapouite/crane.html |
| `art/icons/avatar_meditate.png` | meditation | Lorc | https://game-icons.net/1x1/lorc/meditation.html |
| `art/icons/boss_dragon.png` | dragon-head | Lorc | https://game-icons.net/1x1/lorc/dragon-head.html |
| `art/icons/boss_tiger.png` | tiger-head | Delapouite | https://game-icons.net/1x1/delapouite/tiger-head.html |
| `art/icons/boss_fox.png` | fox-head | Lorc | https://game-icons.net/1x1/lorc/fox-head.html |
| `art/icons/boss_wolf.png` | wolf-head | Lorc | https://game-icons.net/1x1/lorc/wolf-head.html |
| `art/icons/boss_snake.png` | snake | Lorc | https://game-icons.net/1x1/lorc/snake.html |
| `art/icons/boss_scorpion.png` | scorpion | Lorc | https://game-icons.net/1x1/lorc/scorpion.html |
| `art/icons/boss_reptile.png` | horned-reptile | Delapouite | https://game-icons.net/1x1/delapouite/horned-reptile.html |
| `art/icons/boss_werewolf.png` | werewolf | Lorc | https://game-icons.net/1x1/lorc/werewolf.html |
| `art/icons/boss_ghost.png` | ghost | Lorc | https://game-icons.net/1x1/lorc/ghost.html |
| `art/icons/boss_skull.png` | skull-crack | Lorc | https://game-icons.net/1x1/lorc/skull-crack.html |
| `art/icons/boss_lizard.png` | lizardman | Lorc | https://game-icons.net/1x1/lorc/lizardman.html |
| `art/icons/boss_turtle.png` | turtle-shell | Lorc | https://game-icons.net/1x1/lorc/turtle-shell.html |
| `art/icons/boss_unicorn.png` | unicorn | Delapouite | https://game-icons.net/1x1/delapouite/unicorn.html |
| `art/icons/boss_twin_dragon.png` | double-dragon | Lorc | https://game-icons.net/1x1/lorc/double-dragon.html |

## 2. 背景画（公有领域的古画，维基共享资源）

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

这些全部由 `tools/assets/build_ui_frames.py` 画出来（PIL，超采样抗锯齿），**没有使用任何外部图片**，版权属于本项目。
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

## 如何替换

1. 同名文件覆盖 `game/assets/art/...`；尺寸可以不同，九宫格边距改 `art_lib.gd` 里的 `NINE`。
2. 物品图标：把 `<物品 slug>.png` 放到 `game/assets/art/items/`，物品格会自动显示原图（不染色）。
3. 换完后在 Godot 里重新导出主题：`godot --headless --path game --script res://scripts/dev/export_theme.gd`。
4. 更新本文件和 `credits.json`；全部换成自有素材后，可以把致谢页里的 CC BY 署名删掉。
