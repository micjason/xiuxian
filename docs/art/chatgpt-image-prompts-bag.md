# 行囊 / 装备 · ChatGPT Image 提示词

给 **ChatGPT 生图（GPT Image / Image 2）** 用。按本仓库 **0.1.13** 已落地的行囊页来写：竖屏 1080×1920，底栏五页不变，行囊页 = **角色居中装备环绕 + 分类网格 + 详情弹窗**。

用法：每次先贴「总风格」，再贴某一条。一次只出一张。图标类一律 **正方形、透明底、居中、不要字**。整页稿可以带字，那是设计稿，不是进游戏的素材。

生成后按 `docs/art/asset-register.md` 登记，再放进 `game/assets/art/`。没有许可证的图不要打进 APK。

---

## 1. 总风格（每次都贴）

```text
Style lock for a vertical mobile idle xianxia game (1080x1920 portrait).
Quiet, premium, not flashy. Dark pine-ink night: charcoal teal #0B1413,
deep moss panels #16211F at 90% opacity, ivory text #EDE8D6, muted sage
#849A91, jade #ADCAB8, antique gold #DBC470.
Soft inner glow, thin gold hairline borders, rounded 16–24px corners.
No neon, no cyberpunk, no anime chibi, no western plate armor, no
crowded UI chrome, no watermarks, no extra logos, no English UI unless
asked. Lighting like lantern mist over wet stone. Painterly but clean
enough to crop into game icons.
```

品质色（描边 / 光晕只用这个，不要整图标换画风）：

| 品质 | 色 | 用途 |
| --- | --- | --- |
| 白 凡铁 | `#DBDBD6` | 细银边 |
| 蓝 灵纹 | `#6B9EEB` | 淡蓝晕 |
| 紫 幽光 | `#B87AEB` | 紫雾 |
| 金 金篆 | `#EBC757` | 金线 |
| 红 劫纹 | `#E65247` | 薄血光 |

---

## 2. 整页设计稿（先出这 3 张，用来对齐版式）

### 2.1 行囊页 · 空装

用途：对照现有代码排版。上：公共顶栏（境界 / 修为 / 战力）。中：装备板。下：Tab + 四列网格。底：五栏。

```text
[paste 总风格]

Full portrait UI mockup 1080x1920, Chinese idle game screen named 行囊.
Top status bar two lines: left 凡人, right 战力 17; second line 修为 0 / 360.
Main pane: dark jade card. Upper half is an equipment paper-doll:
empty rounded slots around a standing young cultivator silhouette in
the center. Slots labeled in Chinese only: 头盔 top, 武器 left, 玉佩
right, 衣服 under the body, 鞋子 at the feet. Empty slots show faint
slot icons, no items.
Below: a count "行囊 0 / 36" and five compact tabs 全部 装备 丹药 材料 功法,
with 全部 selected in gold.
A 4-column empty item grid with dashed cells.
Bottom tab bar 修炼 历练 行囊 功法 设置, 行囊 highlighted gold.
No extra windows. Clean spacing, thumb-reach primary area on the grid.
```

建议文件：`content-source/ui/bag_page_empty.png`  
进游戏：不进。只当对照稿。

### 2.2 行囊页 · 已穿 + 有物

```text
[paste 总风格]

Same 1080x1920 行囊 screen as a lived-in state.
Center cultivator now wears rustic starter gear: pale wooden sword,
vine helmet, coarse cloth robe, old cloth shoes, a dull green pebble
pendant. Each worn piece sits in its surrounding slot with a thin
white-quality silver rim.
Below tabs, 全部 is selected. Grid shows 8 items in 4 columns:
two white pills, two materials (grass, bone), two skill-book pages,
two spare white weapons. Equipped items do NOT appear in the grid.
Cell captions can be tiny Chinese 2–4 characters. Quality-colored
thin borders. No inspect popup yet.
```

建议文件：`content-source/ui/bag_page_filled.png`

### 2.3 装备详情弹窗（盖在行囊上）

```text
[paste 总风格]

Same 1080x1920 行囊 page dimmed to 72% black-teal.
Centered large rounded card (~720x840) floating above the grid.
Card title 削木剑 in ivory, white-quality silver hairline.
A large 256px wooden sword icon in a square well.
Lines in Chinese:
白色 · 武器 · 装备
词条  凡铁 · 破势
攻5  防0.6  速0.4
装备战力 6
可以穿戴。该槽位空着。
换上后 战力 17 → 23（+6）
Three wide buttons in a row: 穿上 上锁 丢弃, plus 关闭 under them.
No extra decorations, no English.
```

建议文件：`content-source/ui/item_inspect_popup.png`

---

## 3. 角色与装备板

### 3.1 中间角色（立绘，透明底）

用途：装备板正中。代码里现在是「境界 + 修士」字，替换成这张。

```text
[paste 总风格]

Full-body standing young Chinese cultivator, front three-quarter,
idle pose, hands empty, no weapon. Simple dark teal travel robe,
hair in a loose bun, calm face, age about 18. No armor plates.
Square 1024x1024, centered, full body visible with headroom,
transparent background, no ground shadow text, no border, no UI.
Soft lantern key light from upper left. Painterly, readable at 160px.
```

建议文件：`game/assets/art/character/cultivator_idle.webp`  
预算：1024×1024 WebP。

变体（可后做）：`cultivator_qi.webp` 炼气气质，衣纹多一点青光；先出凡人即可。

### 3.2 空槽框（5 张，同一套）

一次一张。把 `{SLOT}` / `{GLYPH}` 换掉。

| 槽 | 文件 ID | 中文 | 空槽暗示物 |
| --- | --- | --- | --- |
| helmet | `slot_helmet_empty` | 头盔 | 浅冠影 |
| weapon | `slot_weapon_empty` | 武器 | 浅剑影 |
| clothes | `slot_clothes_empty` | 衣服 | 浅袍影 |
| shoes | `slot_shoes_empty` | 鞋子 | 浅履影 |
| accessory | `slot_accessory_empty` | 玉佩 | 浅坠影 |

```text
[paste 总风格]

UI slot frame 512x512, transparent background.
Rounded square well, dark moss fill, thin antique-gold hairline,
very faint inner glyph of a {GLYPH}, low contrast, no text,
no item, no character, no sparkles. Must stay readable at 72px.
```

例：头盔把 `{GLYPH}` 换成 `simple crown silhouette`。

### 3.3 品质槽框（5 品质 × 可共用）

空槽是金细边；有装备时边框跟品质走。可先出 5 个通用框，套在任何图标外。

```text
[paste 总风格]

Empty rounded item frame 512x512, transparent outside.
Dark teal well, 3px rim in {QUALITY_COLOR}, tiny matching corner
motes, no icon inside, no text. Consistent thickness so frames
can overlay any item icon.
```

`{QUALITY_COLOR}` 用第 1 节的五色。

---

## 4. 装备图标（进网格 + 进槽 + 进弹窗）

规则：

- 正方形 **512×512**，透明底，物体居中，四周留 10% 空。
- **不要字、不要品质框**（框由游戏叠）。
- 同一件装备只出一张，白蓝紫金红用「材质 + 光」区分，不换外形。
- 弹窗放大用同一张，不要另画一张大图。

公共模板：

```text
[paste 总风格]

Game item icon 512x512, transparent background, object centered,
no text, no frame, no UI, no ground plane.
{ITEM_DESCRIPTION}
Quality feel: {QUALITY_LOOK}. Readable at 88px and at 256px.
```

### 4.1 按槽位的「族」提示（先出每槽 1 白 1 蓝，对齐手感）

| 槽 | 白（凡人） | 蓝（青石涧） | 画什么 |
| --- | --- | --- | --- |
| 武器 | 削木剑 `sword_0` | 青石剑 `sword_2` | 单手短剑，木质 → 青石刃 |
| 头盔 | 藤盔 `helm_0` | 石纹盔 `helm_2` | 轻盔，藤条 → 石纹 |
| 衣服 | 粗布衣 `robe_0` | 涧蓝衣 `robe_2` | 交领袍，粗布 → 涧蓝 |
| 鞋子 | 旧布鞋 `boots_0` | 湿岩靴 `boots_2` | 布鞋 → 湿岩石纹靴 |
| 玉佩 | 青石坠 `jade_0` | 水纹佩 `jade_2` | 石坠 → 水波玉佩 |

`{QUALITY_LOOK}`：

- 白：`dry mundane materials, faint silver dust, no glow`
- 蓝：`cool river-blue spirit lines, soft glow`
- 紫：`dusk purple haze, bone or ember undertone`
- 金：`antique gold inlay, warm lantern bloom`
- 红：`thin crimson rift light, ancient stone`

### 4.2 逐件提示词（复制后只改花括号）

**削木剑 `sword_0`**

```text
[paste 总风格 + 公共模板]

{ITEM_DESCRIPTION} = a short rustic sword, pale unfinished wood blade
and simple cord-wrapped hilt, chips on the edge, hanging at a slight
angle.
{QUALITY_LOOK} = dry mundane wood, faint silver dust, no glow
```

**藤盔 `helm_0`**

```text
a light helmet woven from green vines and thin bamboo, inner cloth
pad visible, not a metal barbute.
{QUALITY_LOOK} = dry mundane materials, faint silver dust, no glow
```

**粗布衣 `robe_0`**

```text
folded coarse hemp xianxia robe, crossed collar, rope belt, no
embroidery, presented as a tidy clothing icon not a mannequin.
```

**旧布鞋 `boots_0`**

```text
a pair of worn grey cloth shoes, patched toe, hemp sole, top-down
three-quarter view.
```

**青石坠 `jade_0`**

```text
a small dull green pebble pendant on a dark cord, slightly irregular,
no carved dragon.
```

**青石剑 `sword_2`**

```text
a straight sword with a blue-grey stone blade, faint water-line veins,
dark wrapped hilt, cleaner silhouette than a wooden practice sword.
{QUALITY_LOOK} = cool river-blue spirit lines, soft glow
```

其余装备按 `adventure.json` 的 `display_name` 换材质即可，外形跟槽位族走：

| id | 名字 | 材质关键词 |
| --- | --- | --- |
| sword_1 | 猎骨刀 | 带齿骨刃短刀 |
| helm_1 | 皮盔 | 兽皮圆盔 |
| robe_1 | 兽皮甲 | 浅褐皮袍甲 |
| boots_1 | 山行靴 | 绑腿布靴 |
| jade_1 | 兽牙坠 | 一颗兽牙 |
| helm_2 | 石纹盔 | 青石灰岩纹 |
| robe_2 | 涧蓝衣 | 深蓝湿布 |
| boots_2 | 湿岩靴 | 深青湿石 |
| jade_2 | 水纹佩 | 水波玉片 |
| sword_3 | 雾鸦枪 | 细枪 + 鸦羽穗 |
| sword_4 | 断魂刃 | 暗紫残刃 |
| sword_5 | 赤焰戟 | 赤铜戟 |
| sword_6 | 沉渊尺 | 墨金镇尺 |
| sword_7 | 古碑剑 | 碑文赤纹长剑 |

高品质件把 `{QUALITY_LOOK}` 换成紫 / 金 / 红那一档。

文件名：`game/assets/art/items/{id}.webp`

---

## 5. 背包网格与分类

### 5.1 空格子

```text
[paste 总风格]

Empty inventory cell 512x512, transparent outside.
Rounded 14px dark well #0C1412, 1px muted gold rim at 40% opacity,
no icon, no plus sign, no text. Identical so it can tile in a 4-column
grid.
```

`ui/bag_cell_empty.webp`

### 5.2 分类 Tab 图标（可选，现在 Tab 是纯字）

5 张，线描小图标，24×24 观感，画 256 即可。

```text
[paste 总风格]

Tiny UI glyph 256x256, transparent background, single color antique
gold line icon, no text, no circle badge.
Subject: {GLYPH}.
```

| Tab | GLYPH |
| --- | --- |
| 全部 | four tiny squares |
| 装备 | simple sword |
| 丹药 | round gourd pill bottle |
| 材料 | two herb leaves |
| 功法 | open thin book |

`ui/tab_all.webp` … `ui/tab_book.webp`

### 5.3 丹药 / 材料 / 功法格图标

**回气丹 `pill_qi_0`**

```text
[paste 总风格 + 公共模板]

a small matte white ceramic pill bottle with a cork, one pale pill
beside it, no label text.
{QUALITY_LOOK} = dry mundane materials, faint silver dust, no glow
```

**养体丹 `pill_body_0`**

```text
a squat ochre pill bottle, warmer clay, two beige pills.
```

**灵草 `mat_spirit_grass`**

```text
three fresh spirit grass blades tied with a hemp thread, dew, no flower.
```

**兽骨 `mat_beast_bone`**

```text
a clean short beast bone, slight yellow ivory, no blood, no skull.
```

**功法残页（共用底，再出 4 阶色）**

```text
a torn yellow xianxia scripture page, brush marks, burnt edge,
rolled slightly, no readable characters (abstract strokes only).
{QUALITY_LOOK} = white / blue / purple / gold / red as specified
```

4 张即可：`book_white.webp` `book_blue.webp` `book_purple.webp` `book_gold.webp`  
红色残页用 `book_red.webp`。具体功法名用同一张底图，游戏叠字。

---

## 6. 弹窗零件

### 6.1 弹窗底板

```text
[paste 总风格]

Nine-slice friendly panel 1024x1024, transparent outside.
Dark moss card #16211F, 24px rounded corners, 2px antique gold rim,
soft inner shadow, empty center, no title, no buttons, no watermark.
Even margins so it can stretch to 720x840.
```

`ui/inspect_panel.webp`

### 6.2 弹窗大图标井

```text
Square icon well 512x512, transparent outside, inset dark pit,
thin gold rim, empty, for placing an item icon in the inspect popup.
```

`ui/inspect_icon_well.webp`

### 6.3 关闭 / 穿上 不必出图

按钮继续用现有金钮和幽灵钮。不要为按钮单独出拟物。

---

## 7. 建议出图顺序

1. **2.1 空行囊整页** — 先看版式，不对就改提示词，不要先画 40 件装备。
2. **2.3 弹窗整页** — 确认信息层级：名 → 图标 → 词条 → 攻防速 → 战力变化 → 按钮。
3. **3.1 角色** + **3.2 五空槽**。
4. 白品质五件套（`sword_0` 到 `jade_0`）+ 丹药材料各 1。
5. **2.2 已穿整页** — 把 4 的图标贴进稿里看密不密。
6. 再补蓝 / 紫 / 金 / 红和剩余刀枪戟尺。

不要一上来让模型出「整套 40 图标一张精灵图」。ChatGPT Image 会糊，后期也难切。

---

## 8. 进游戏时的尺寸

| 用途 | 画布 | 运行时大约 |
| --- | --- | --- |
| 整页设计稿 | 1080×1920 | 不进包 |
| 角色 | 1024×1024 | 装备板中约 160×200 |
| 槽框 / 物品 / 格子 | 512×512 | 槽 72、格 88、弹窗 256 |
| Tab 线标 | 256×256 | 28 |
| 弹窗底板 | 1024×1024 | 九宫拉伸 |

导出优先 **WebP**，透明，不要 JPG。

---

## 9. 和代码的对应（给自己对照）

- 装备板节点：`DollBoard`；五槽：武器 / 头盔 / 衣服 / 鞋子 / 玉佩。
- 网格：`BagList`，4 列；已穿 uid **不会**出现在格子里。
- Tab：全部、装备、丹药、材料、功法。
- 弹窗：`ItemInspectLayer` + `ItemInspectCard`。
- 装备可见数：攻、防、速、品质词条；装备战力 = `攻 + 防×0.8 + 速×1.5 + 血×0.04`。
- 穿上后弹窗写人物战力 `旧 → 新（差）`。

出图时不要发明第六槽、套装栏、星级、强化等级。那些不在这一版。
