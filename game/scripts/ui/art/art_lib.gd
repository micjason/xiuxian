class_name ArtLib
extends RefCounted
## 美术资源的唯一入口：背景、图标、九宫格框体、字体都从这里取。
## 资源都在 res://assets/art/ 和 res://assets/fonts/，来源与授权见 res://assets/ASSETS_LICENSES.md。
## 换成正式美术：同名文件覆盖即可（九宫格边距在 NINE 表里），业务代码不用动。
## 找不到资源时会 push_warning 并返回 null，调用方显示占位，不会静默换成别的图。

const UI_DIR := "res://assets/art/ui/"
const ICON_DIR := "res://assets/art/icons/"
const BG_DIR := "res://assets/art/bg/"
const ITEM_DIR := "res://assets/art/items/"
const FONT_BODY := "res://assets/fonts/NotoSansSC-Regular.subset.woff2"
const FONT_TITLE := "res://assets/fonts/MaShanZheng-Regular.subset.woff2"

## 九宫格：名称 → [左右边距, 上下边距, 内容横向边距, 内容纵向边距]
const NINE := {
	"panel_card": [32, 32, 28, 24],
	"panel_popup": [48, 48, 36, 32],
	# 离线收益卷轴外框（清单 N158，参考图 984×1350）：左右 40 盖住轴头，上下 116 盖住轴头和投影；内容安全区 56 / 100。
	"panel_popup_scroll": [40, 116, 56, 100],
	"panel_inset": [24, 24, 20, 16],
	"ribbon_title": [64, 30, 56, 12],
	# 页面标题牌（暗色牌）：美术第 3 轮把 ribbon_title 交成了红色两端平切的卷轴缎带（只用在弹窗标题），
	# 页面标题仍用此前的暗色牌，文件是仓库里原来的 ribbon_title.png 另存的，等美术补正式图（见 art-integration 说明）。
	"page_title_plate": [64, 30, 56, 12],
	# 2026-10-16 交付：战报面板（N119）、新手引导气泡（N144）、引导高亮框（N146）。引导两张原型里还没有界面用到，先登记边距。
	"battle_log_panel": [40, 40, 20, 16],
	"guide_bubble": [40, 40, 28, 20],
	"guide_highlight": [48, 48, 0, 0],
	"chip": [30, 24, 28, 8],
	"toast": [32, 32, 28, 20],
	"row_bg": [20, 20, 24, 18],
	"row_selected": [22, 22, 24, 18],
	"btn_primary_normal": [36, 36, 28, 16],
	"btn_primary_pressed": [36, 36, 28, 16],
	"btn_primary_disabled": [36, 36, 28, 16],
	"btn_secondary_normal": [36, 36, 28, 16],
	"btn_secondary_pressed": [36, 36, 28, 16],
	"btn_secondary_disabled": [36, 36, 28, 16],
	"btn_danger_normal": [36, 36, 28, 16],
	"btn_danger_pressed": [36, 36, 28, 16],
	"btn_danger_disabled": [36, 36, 28, 16],
	"btn_jade_normal": [36, 36, 28, 16],
	"btn_jade_pressed": [36, 36, 28, 16],
	"btn_jade_disabled": [36, 36, 28, 16],
	"btn_ghost_normal": [36, 36, 28, 16],
	"btn_ghost_pressed": [36, 36, 28, 16],
	"btn_ghost_disabled": [36, 36, 28, 16],
	"bar_frame": [30, 22, 0, 0],
	"bar_fill_jade": [26, 20, 0, 0],
	"bar_fill_gold": [26, 20, 0, 0],
	"bar_fill_cin": [26, 20, 0, 0],
	"bar_fill_blue": [26, 20, 0, 0],
	"slot_empty": [30, 30, 0, 0],
	"slot_locked": [30, 30, 0, 0],
	"slot_selected": [30, 30, 0, 0],
	"slot_r0": [30, 30, 0, 0],
	"slot_r1": [30, 30, 0, 0],
	"slot_r2": [30, 30, 0, 0],
	"slot_r3": [30, 30, 0, 0],
	"slot_r4": [30, 30, 0, 0],
	"slot_r5": [30, 30, 0, 0],
}

## 物品图标回退用的 id。大境界 id 和服务端方案内容一致（numeric-scheme.ts 的 MAJORS）；
## 原型只用前 3 个，后两个先登记，美术以后补图即自动生效。
const REALM_IDS: Array[String] = ["qi", "foundation", "core", "infant", "spirit"]
## 装备部位 id，和 SlotConfig.CORE 一致（服务端 GEAR_SLOTS 同名）。
const GEAR_SLOT_IDS: Array[String] = ["weapon", "helmet", "clothes", "gloves", "shoes", "accessory"]
## 非装备物品的类别规则：[kind 或 category, 物品 slug 里出现的片段, 回退文件名（不含 .png）]。
## 片段只在 slug 里找；都不命中时用 <前缀>_other。
const ITEM_KIND_RULES := [
	["material", "enh_stone_", "mat_stone"],
	["material", "grass", "mat_herb"],
	["material", "herb", "mat_herb"],
	["material", "bone", "mat_bone"],
	["skill_book", "_atk_", "book_atk"],
	["skill_book", "_def_", "book_def"],
	["skill_book", "_hp_", "book_hp"],
	["pill", "pill_qi", "pill_qi"],
	["pill", "pill_body", "pill_body"],
]
const ITEM_KIND_OTHER := {"material": "mat_other", "skill_book": "book_other", "pill": "pill_other"}
## 还没交付、但代码已经按名字取的界面贴图（自动分解开关）。
const SWITCH_ON := "switch_on"
const SWITCH_OFF := "switch_off"

static var _cache: Dictionary = {}
static var _fonts: Dictionary = {}


static func _load(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		push_warning("缺少美术资源：%s" % path)
	_cache[path] = tex
	return tex


static func ui(name: String) -> Texture2D:
	return _load(UI_DIR + name + ".png")


static func icon(name: String) -> Texture2D:
	return _load(ICON_DIR + name + ".png")


static func bg(name: String) -> Texture2D:
	return _load(BG_DIR + name + ".webp")


## 图标没交付时用 fallback 顶上（占位）。例如页签「洞府」的 tab_cave（N160）还没出图。
static func icon_or(name: String, fallback: String) -> Texture2D:
	return icon(name) if has_icon(name) else icon(fallback)


static func has_ui(name: String) -> bool:
	return ResourceLoader.exists(UI_DIR + name + ".png")


static func has_icon(name: String) -> bool:
	return ResourceLoader.exists(ICON_DIR + name + ".png")


## 开关贴图（160×80）。没交付时返回 null，调用方画占位。
static func switch_tex(on: bool) -> Texture2D:
	return ui(SWITCH_ON if on else SWITCH_OFF)


## 九宫格样式盒。modulate 可以给 hover 等状态提亮。
static func nine(name: String, modulate: Color = Color.WHITE) -> StyleBoxTexture:
	var spec: Array = NINE.get(name, [32, 32, 24, 16])
	var box := StyleBoxTexture.new()
	box.texture = ui(name)
	box.texture_margin_left = spec[0]
	box.texture_margin_right = spec[0]
	box.texture_margin_top = spec[1]
	box.texture_margin_bottom = spec[1]
	box.content_margin_left = spec[2]
	box.content_margin_right = spec[2]
	box.content_margin_top = spec[3]
	box.content_margin_bottom = spec[3]
	box.modulate_color = modulate
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return box


static func body_font() -> Font:
	return _font("body")


static func title_font() -> Font:
	return _font("title")


## 加粗的正文：对常规字重做合成加粗，避免多带一个字体文件。
static func bold_font() -> Font:
	return _font("bold")


static func _font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var variation := FontVariation.new()
	match kind:
		"title":
			variation.base_font = _file_font(FONT_TITLE)
		"bold":
			variation.base_font = _file_font(FONT_BODY)
			variation.variation_embolden = 0.55  # 合成加粗，避免多带一个字体文件
		_:
			variation.base_font = _file_font(FONT_BODY)
	# 子集字体只含 GB2312 一级汉字和游戏里出现过的字；服务器下发的生僻字退回系统字体，不会显示成方块。
	# 回退字体挂在 FontVariation 上，导出主题时会一起存进 .tres。
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["PingFang SC", "Noto Sans CJK SC", "Source Han Sans SC", "Noto Sans SC", "WenQuanYi Micro Hei", "sans-serif"])
	variation.fallbacks = [system]
	_fonts[kind] = variation
	return variation


static func _file_font(path: String) -> Font:
	var file := load(path) as Font
	if file == null:
		push_warning("缺少字体：%s" % path)
		return FontFile.new()
	return file


## 稀有度对应的 slot_r* 框
static func slot_frame(rarity: int) -> String:
	return "slot_r%d" % clampi(rarity, 0, 5)


## 部位 id → 图标名
static func slot_icon_name(slot_id: String) -> String:
	return "slot_%s" % slot_id


## 物品类别 → 图标名（没有专属图标的物品用类别图标）
static func category_icon_name(category: String, kind: String = "") -> String:
	if kind == "skill_book":
		return "cat_book"
	match category:
		"equip":
			return "cat_equipment"
		"material":
			return "cat_material"
		"pill":
			return "cat_pill"
		_:
			return "cat_other"


## 首领头像：按名字稳定地挑一个，同一个首领永远是同一张。
static func boss_icon_name(boss_name: String) -> String:
	const KEYS := [
		["龙", "蛟", "boss_dragon"], ["虎", "boss_tiger"], ["狐", "boss_fox"], ["狼", "boss_wolf"], ["蛇", "蟒", "boss_snake"],
		["蝎", "boss_scorpion"], ["鬼", "魂", "幽", "boss_ghost"], ["骨", "尸", "boss_skull"], ["龟", "玄武", "boss_turtle"],
		["兽", "狮", "boss_unicorn"],
	]
	for entry in KEYS:
		for index in entry.size() - 1:
			if boss_name.contains(str(entry[index])):
				return str(entry[entry.size() - 1])
	const POOL := ["boss_reptile", "boss_werewolf", "boss_lizard", "boss_twin_dragon", "boss_wolf", "boss_tiger", "boss_dragon", "boss_scorpion"]
	return POOL[absi(boss_name.hash()) % POOL.size()]


## ---- 物品图标回退 ----
## 查找顺序（item 是 BagModel.normalize 出来的字典）：
##   1. items/<slug>.png                         这个物品自己的图
##   2. items/gear_<境界>_<部位>.png             装备：同大境界同部位的代表图
##      items/mat_<类别>.png / book_<类别>.png / pill_<类别>.png   非装备：同类别的代表图
##   3. items/gear_<部位>.png                    装备：只按部位的通用图（非装备没有这一层）
##   4. 现有占位：icons/slot_<部位>.png 或 icons/cat_*.png 白色剪影（按品质染色）
## 前三层是彩色图，不染色；第 4 层是剪影，tint=true。


## 装备所属大境界 id；认不出返回空字符串。先看 slug（gear_<境界>_<部位>_<品质>），再看 required_realm_order（每 3 层一个大境界）。
static func item_realm_id(item: Dictionary) -> String:
	var parts := str(item.get("slug", "")).split("_")
	if parts.size() >= 4 and parts[0] == "gear" and REALM_IDS.has(parts[1]):
		return parts[1]
	var order := int(item.get("required_realm_order", 0))
	if order >= 1:
		var index := floori((order - 1) / 3.0)
		if index < REALM_IDS.size():
			return REALM_IDS[index]
	return ""


## 非装备物品的类别回退名（如 mat_stone）；装备或认不出 kind 返回空字符串。
static func item_kind_fallback(item: Dictionary) -> String:
	var kind := str(item.get("kind", ""))
	if kind == "equipment" or not ITEM_KIND_OTHER.has(kind):
		return ""
	var slug := str(item.get("slug", ""))
	for rule in ITEM_KIND_RULES:
		if rule[0] == kind and slug.contains(str(rule[1])):
			return str(rule[2])
	return str(ITEM_KIND_OTHER[kind])


## 按优先级排好的候选文件名（不含目录和 .png），不碰文件系统，方便测试。
static func item_icon_candidates(item: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var slug := str(item.get("slug", ""))
	if not slug.is_empty():
		out.append(slug)
	var slot_id := str(item.get("slot_id", ""))
	if GEAR_SLOT_IDS.has(slot_id):
		var realm := item_realm_id(item)
		if not realm.is_empty():
			out.append("gear_%s_%s" % [realm, slot_id])
		out.append("gear_%s" % slot_id)
	else:
		var fallback := item_kind_fallback(item)
		if not fallback.is_empty():
			out.append(fallback)
	return out


## 返回 {texture, tint, source}。source = 命中的文件名，没命中前三层时是 "placeholder"。texture 可能为 null。
## exists 只给测试用（传入自定义的存在判断）；平时用 ResourceLoader。
static func item_icon(item: Dictionary, exists: Callable = Callable()) -> Dictionary:
	for name in item_icon_candidates(item):
		var path := ITEM_DIR + name + ".png"
		var found: bool = exists.call(path) if exists.is_valid() else ResourceLoader.exists(path)
		if found:
			var tex: Texture2D = null
			if not exists.is_valid():
				tex = load(path) as Texture2D
			return {"texture": tex, "tint": false, "source": name}
	var slot_id := str(item.get("slot_id", ""))
	if not slot_id.is_empty() and has_icon(slot_icon_name(slot_id)):
		return {"texture": icon(slot_icon_name(slot_id)), "tint": true, "source": "placeholder"}
	var cat := category_icon_name(str(item.get("category", "")), str(item.get("kind", "")))
	return {"texture": icon(cat), "tint": true, "source": "placeholder"}


## 美术需要交付的全部回退图文件名（不含目录和 .png）。原型阶段只含前 3 个大境界。
## 和 /workspace/art_item_icon_fallback_spec.md 第 7 节一一对应。
const PROTOTYPE_REALM_COUNT := 3


static func fallback_filenames() -> Array[String]:
	var out: Array[String] = []
	for realm in REALM_IDS.slice(0, PROTOTYPE_REALM_COUNT):
		for slot in GEAR_SLOT_IDS:
			out.append("gear_%s_%s" % [realm, slot])
	for slot in GEAR_SLOT_IDS:
		out.append("gear_%s" % slot)
	var seen := {}
	for rule in ITEM_KIND_RULES:
		seen[str(rule[2])] = true
	for kind in ITEM_KIND_OTHER:
		seen[str(ITEM_KIND_OTHER[kind])] = true
	var names: Array = seen.keys()
	names.sort()
	for name in names:
		out.append(str(name))
	return out
