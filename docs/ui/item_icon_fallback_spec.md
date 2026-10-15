# 物品图标回退规格（给美术）

- 日期：2026-10-16　版本：v1（以代码为准：`game/scripts/ui/art/art_lib.gd` 的 `ArtLib.item_icon`）
- 决定：负责人/Chengpeng 已同意“按部位和境界回退”。灵宠、法宝、广告、每日任务不在本规格内。
- **目的：** 线上物品有 200+ 个 slug，不可能逐个画。游戏会先找这个物品自己的图；找不到就退到“同境界同部位”的代表图；再找不到退到“只按部位”的通用图；最后才是现有的白色剪影占位。所以**先画下面 35 张就能让原型里所有物品都有图**，品质靠代码叠的品质框和光晕区分。

## 1. 通用规格

| 项 | 要求 |
|---|---|
| 目录 | 全部放在 `res://assets/art/items/`，**平铺，不要子目录**，文件名全小写，扩展名 `.png` |
| 尺寸 | **256×256 px，1x**（和切图清单 A116 物品图标一致；不交 @2x） |
| 格式 | PNG（RGBA，sRGB），透明底，只画物品本身，**不画品质框、不画底板、不画光晕**（这些由代码叠） |
| 着色 | **彩色原图，代码不染色**（和 `icons/` 里的白色剪影不同） |
| 构图 | 主体放在中间约 66%（显示时实际约 116 px），轮廓要一眼看出是哪个部位/哪类物品；四周留透明边 |
| 品质 | 回退图要“中性品质”：不要把某个品质的颜色画死（比如全金边），否则白装和橙装看起来一样。品质由框区分 |
| 境界差异 | 同一部位三张图（炼气/筑基/金丹）要能看出档次递进：材质、纹饰、复杂度逐级提高，但**轮廓保持同一部位的识别特征** |
| 体积 | ≤40 KB/张（切图清单预算） |

## 2. 查找顺序（代码实际行为）

装备（有部位）：
1. `items/<slug>.png`，例 `gear_qi_weapon_white.png`（物品自己的图，以后有就自动用）
2. `items/gear_<境界>_<部位>.png`，例 `gear_qi_weapon.png`
3. `items/gear_<部位>.png`，例 `gear_weapon.png`（只按部位）
4. 现有占位：`icons/slot_<部位>.png` 白色剪影，按品质染色

非装备（突破石、功法书、丹药）：
1. `items/<slug>.png`
2. `items/<类别文件>.png`，例 `mat_stone.png`（类别怎么认见第 5 节）
3. 现有占位：`icons/cat_material.png` / `cat_book.png` / `cat_pill.png` / `cat_other.png`

装备的境界取自 slug 里的 `gear_<境界>_…`；slug 不是这个格式时，用物品的“需要境界序号”换算（每 3 层一个大境界）。

## 3. id 对照（来自代码，一个字符都不能差）

**境界 id**（服务端 `numeric-scheme.ts` 的 `MAJORS`，也是 `gear_<境界>_…` 里的那一段）：

| id | 名称 | 本轮原型 |
|---|---|---|
| `qi` | 炼气 | ✅ 要画 |
| `foundation` | 筑基 | ✅ 要画 |
| `core` | 金丹 | ✅ 要画 |
| `infant` | 元婴 | 暂不画（代码已登记，以后补图自动生效） |
| `spirit` | 化神 | 暂不画（代码已登记，以后补图自动生效） |

**部位 id**（服务端 `gear.ts` 的 `GEAR_SLOTS`；客户端 `slot_config.gd` 的 `CORE`）：

| id | 名称 |
|---|---|
| `weapon` | 武器 |
| `helmet` | 头部 |
| `clothes` | 身体 |
| `gloves` | 手部 |
| `shoes` | 腿/鞋 |
| `accessory` | 饰品 |

（`artifact` 法宝、`pet` 灵宠是预留位，没有物品，不需要回退图。）

## 4. 装备回退图：24 张

### 4.1 境界 × 部位（18 张，优先画）

文件名 `gear_<境界>_<部位>.png`

| 文件名 | 说明 |
|---|---|
| `gear_qi_weapon.png` | 炼气·武器 |
| `gear_qi_helmet.png` | 炼气·头部 |
| `gear_qi_clothes.png` | 炼气·身体 |
| `gear_qi_gloves.png` | 炼气·手部 |
| `gear_qi_shoes.png` | 炼气·腿/鞋 |
| `gear_qi_accessory.png` | 炼气·饰品 |
| `gear_foundation_weapon.png` | 筑基·武器 |
| `gear_foundation_helmet.png` | 筑基·头部 |
| `gear_foundation_clothes.png` | 筑基·身体 |
| `gear_foundation_gloves.png` | 筑基·手部 |
| `gear_foundation_shoes.png` | 筑基·腿/鞋 |
| `gear_foundation_accessory.png` | 筑基·饰品 |
| `gear_core_weapon.png` | 金丹·武器 |
| `gear_core_helmet.png` | 金丹·头部 |
| `gear_core_clothes.png` | 金丹·身体 |
| `gear_core_gloves.png` | 金丹·手部 |
| `gear_core_shoes.png` | 金丹·腿/鞋 |
| `gear_core_accessory.png` | 金丹·饰品 |

### 4.2 只按部位（6 张，兜底）

文件名 `gear_<部位>.png`。境界图缺失时（例如以后加了元婴、化神但还没画）用它。画成“中档、无明显境界特征”的通用款。

| 文件名 | 说明 |
|---|---|
| `gear_weapon.png` | 武器（通用） |
| `gear_helmet.png` | 头部（通用） |
| `gear_clothes.png` | 身体（通用） |
| `gear_gloves.png` | 手部（通用） |
| `gear_shoes.png` | 腿/鞋（通用） |
| `gear_accessory.png` | 饰品（通用） |

## 5. 非装备回退图：11 张

类别从代码和现有内容里得出（只有这些，没有别的）：

| 文件名 | 什么物品会用它 | 判定规则（物品 kind + slug 片段） |
|---|---|---|
| `mat_stone.png` | 突破石（下/中/上品，`enh_stone_low/mid/high`） | material + slug 含 `enh_stone_` |
| `mat_herb.png` | 灵草等草药（旧版 `mat_spirit_grass`） | material + slug 含 `grass` 或 `herb` |
| `mat_bone.png` | 兽骨等骨材（旧版 `mat_beast_bone`） | material + slug 含 `bone` |
| `mat_other.png` | 其他材料 | material，上面都不命中 |
| `book_atk.png` | 攻击类功法书（`book_skill_<境界>_atk_<阶>`） | skill_book + slug 含 `_atk_` |
| `book_def.png` | 防御类功法书（`…_def_…`） | skill_book + slug 含 `_def_` |
| `book_hp.png` | 气血类功法书（`…_hp_…`） | skill_book + slug 含 `_hp_` |
| `book_other.png` | 其他功法书（旧版 `book_tuna` 等） | skill_book，上面都不命中 |
| `pill_qi.png` | 回气类丹药（旧版 `pill_qi_0`） | pill + slug 含 `pill_qi` |
| `pill_body.png` | 养体类丹药（旧版 `pill_body_0`） | pill + slug 含 `pill_body` |
| `pill_other.png` | 其他丹药 | pill，上面都不命中 |

功法书的阶（黄/玄/地/天）和境界不进文件名，靠品质框区分；如果美术想让阶有差别，可以在书脊/封签上做颜色提示，但**同一类别只交一张**。

## 6. 总清单（35 张）

| 组 | 数量 | 优先级 |
|---|---|---|
| 装备 境界×部位 `gear_<境界>_<部位>.png` | 18 | P0 |
| 装备 只按部位 `gear_<部位>.png` | 6 | P1 |
| 突破石/材料 `mat_stone` `mat_herb` `mat_bone` `mat_other` | 4 | P0（`mat_stone` 最先：突破石是强化必用材料） |
| 功法书 `book_atk` `book_def` `book_hp` `book_other` | 4 | P1 |
| 丹药 `pill_qi` `pill_body` `pill_other` | 3 | P2（原型没有丹药掉落，现有内容里只有旧版两种） |

**可选，不算在 35 张里：** 3 个突破石各自的图 `enh_stone_low.png` / `enh_stone_mid.png` / `enh_stone_high.png`（物品自己的图，优先于 `mat_stone`）。有时间再画。

## 7. 完整文件名（复制用）

```
gear_qi_weapon.png
gear_qi_helmet.png
gear_qi_clothes.png
gear_qi_gloves.png
gear_qi_shoes.png
gear_qi_accessory.png
gear_foundation_weapon.png
gear_foundation_helmet.png
gear_foundation_clothes.png
gear_foundation_gloves.png
gear_foundation_shoes.png
gear_foundation_accessory.png
gear_core_weapon.png
gear_core_helmet.png
gear_core_clothes.png
gear_core_gloves.png
gear_core_shoes.png
gear_core_accessory.png
gear_weapon.png
gear_helmet.png
gear_clothes.png
gear_gloves.png
gear_shoes.png
gear_accessory.png
mat_stone.png
mat_herb.png
mat_bone.png
mat_other.png
book_atk.png
book_def.png
book_hp.png
book_other.png
pill_qi.png
pill_body.png
pill_other.png
```

## 8. 交付与验收

- 交付路径：`game/assets/art/items/`（同切图清单第 4 节的目录结构）。文件名不对（多一个下划线、大小写）时游戏不会报错，只会悄悄退回占位，所以请对照第 7 节逐个检查。
- 开发在 `ArtLib.fallback_filenames()` 里维护这 35 个文件名，GUT 测试检查数量和命名；交付后请在 `ASSETS_LICENSES.md` 登记来源与授权（AI 出图请写明工具与商用授权）。
- 首批可先交 P0（18 + 4 = 22 张），原型就能全部有图。

## 9. 同时新增的两张界面贴图（背包“自动分解”开关）

| 文件 | 尺寸 | 说明 |
|---|---|---|
| `ui/switch_on.png` | 160×80 | 开关打开状态，透明底，彩色（打开用金色/玉色，和主按钮不冲突即可） |
| `ui/switch_off.png` | 160×80 | 开关关闭状态，透明底，彩色（灰暗） |

代码入口 `ArtLib.switch_tex(on)`，没交付之前返回空，界面会用占位。
