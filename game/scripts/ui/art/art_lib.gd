class_name ArtLib
extends RefCounted
## 美术资源的唯一入口：背景、图标、九宫格框体、字体都从这里取。
## 资源都在 res://assets/art/ 和 res://assets/fonts/，来源与授权见 res://assets/ASSETS_LICENSES.md。
## 换成正式美术：同名文件覆盖即可（九宫格边距在 NINE 表里），业务代码不用动。
## 找不到资源时会 push_warning 并返回 null，调用方显示占位，不会静默换成别的图。

const UI_DIR := "res://assets/art/ui/"
const ICON_DIR := "res://assets/art/icons/"
const BG_DIR := "res://assets/art/bg/"
const FONT_BODY := "res://assets/fonts/NotoSansSC-Regular.subset.woff2"
const FONT_TITLE := "res://assets/fonts/MaShanZheng-Regular.subset.woff2"

## 九宫格：名称 → [左右边距, 上下边距, 内容横向边距, 内容纵向边距]
const NINE := {
	"panel_card": [32, 32, 28, 24],
	"panel_popup": [48, 48, 36, 32],
	"panel_inset": [24, 24, 20, 16],
	"ribbon_title": [64, 30, 56, 12],
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


static func has_icon(name: String) -> bool:
	return ResourceLoader.exists(ICON_DIR + name + ".png")


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
