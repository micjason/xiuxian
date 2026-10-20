class_name ItemSlot
extends Button
## 行囊里的一个物品格：品质框、图标、品质光晕、堆叠数量、强化等级、新获得红点、已穿戴标记、多选勾。
## 数据来自 BagModel.normalize() 的展示字典；空格用 set_empty()。
## Q 版：品质色圆角方块 + 可可描边，角标白字可可描边（设计稿 q_bag）。
## 最小边长 132 画布像素（≈ 48dp），一行 6 格放得下。美术接入见 KitStyle / ArtLib。

signal item_pressed(item: Dictionary)

const MIN_SIZE := 132
const ICON_INSET := 14

var item: Dictionary = {}
var selected := false
var dimmed := false

var _glow: TextureRect
var _icon_tex: TextureRect
var _glyph: Label
var _count: Label
var _enhance: Label
var _new: TextureRect
var _equipped: Label
var _check: Label


func _init() -> void:
	custom_minimum_size = Vector2(MIN_SIZE, MIN_SIZE)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_NONE
	clip_text = true
	text = ""
	_build()
	pressed.connect(func() -> void: item_pressed.emit(item))


func _build() -> void:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	_glow = TextureRect.new()
	_glow.texture = ArtLib.ui("glow_soft")
	_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.visible = false
	layer.add_child(_glow)
	_icon_tex = TextureRect.new()
	_icon_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon_tex.offset_left = ICON_INSET
	_icon_tex.offset_top = ICON_INSET
	_icon_tex.offset_right = -ICON_INSET
	_icon_tex.offset_bottom = -ICON_INSET
	_icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_tex.visible = false
	layer.add_child(_icon_tex)
	_glyph = _corner(layer, UiTokens.FS_H2, Control.PRESET_FULL_RECT, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	_count = _corner(layer, UiTokens.FS_CAPTION, Control.PRESET_BOTTOM_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_BOTTOM)
	_enhance = _corner(layer, UiTokens.FS_MICRO, Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP)
	_enhance.add_theme_color_override("font_color", UiTokens.Q_WHITE)
	_new = TextureRect.new()
	_new.texture = ArtLib.ui("reddot")
	_new.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_new.offset_left = -26
	_new.offset_right = 8
	_new.offset_top = -8
	_new.offset_bottom = 26
	_new.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_new.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_new.visible = false
	layer.add_child(_new)
	_equipped = _corner(layer, UiTokens.FS_MICRO, Control.PRESET_BOTTOM_LEFT, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_BOTTOM)
	_equipped.text = "穿"
	_equipped.add_theme_color_override("font_color", UiTokens.Q_MINT_LIGHT)
	_check = _corner(layer, UiTokens.FS_BODY, Control.PRESET_TOP_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_TOP)
	_check.text = "✓"
	_check.add_theme_color_override("font_color", UiTokens.Q_ORANGE)
	_check.visible = false


func _corner(parent: Control, size: int, preset: int, h: int, v: int) -> Label:
	var node := Label.new()
	node.set_anchors_preset(preset as Control.LayoutPreset)
	if preset != Control.PRESET_FULL_RECT:
		node.offset_left = 8 if h == HORIZONTAL_ALIGNMENT_LEFT else -120
		node.offset_right = 120 if h == HORIZONTAL_ALIGNMENT_LEFT else -8
		node.offset_top = 2 if v == VERTICAL_ALIGNMENT_TOP else -50
		node.offset_bottom = 48 if v == VERTICAL_ALIGNMENT_TOP else -2
		if h == HORIZONTAL_ALIGNMENT_LEFT:
			node.anchor_right = node.anchor_left
		else:
			node.anchor_left = node.anchor_right
	node.horizontal_alignment = h as HorizontalAlignment
	node.vertical_alignment = v as VerticalAlignment
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_font_override("font", ArtLib.title_font())
	node.add_theme_color_override("font_color", UiTokens.Q_WHITE)
	node.add_theme_color_override("font_outline_color", UiTokens.Q_COCOA)
	node.add_theme_constant_override("outline_size", 10)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func set_item(data: Dictionary) -> void:
	item = data
	disabled = false
	var rarity := int(data.get("rarity", 0))
	var color := UiTokens.rarity_color(rarity)
	var art := KitStyle.icon_for(data)
	var tex := art.get("texture", null) as Texture2D
	_icon_tex.texture = tex
	_icon_tex.visible = tex != null
	_icon_tex.modulate = color.darkened(0.15) if bool(art.get("tint", false)) else Color.WHITE
	_glow.visible = false  # Q 版靠品质底色区分，不再加光晕
	_glow.modulate = Color(color, KitStyle.glow_alpha(rarity))
	_glyph.text = "" if tex != null else KitStyle.glyph_of(data)
	_glyph.add_theme_color_override("font_color", Color.WHITE)
	var qty := int(data.get("qty", 1))
	_count.text = ("×%d" % qty) if qty > 1 else ""
	var enhance := int(data.get("enhance", 0))
	_enhance.text = ("+%d" % enhance) if enhance > 0 else ""
	_new.visible = bool(data.get("is_new", false))
	_equipped.visible = bool(data.get("equipped", false))
	tooltip_text = "%s · %s" % [str(data.get("name", "")), str(data.get("rarity_name", ""))]
	_restyle()


func set_empty() -> void:
	item = {}
	selected = false
	for node in [_glow, _icon_tex, _glyph, _count, _enhance, _new, _equipped, _check]:
		(node as CanvasItem).visible = false
	disabled = true
	tooltip_text = ""
	_restyle()


func set_selected(value: bool) -> void:
	selected = value
	_check.visible = value and not item.is_empty()
	_restyle()


func set_dimmed(value: bool) -> void:
	dimmed = value
	modulate = Color(1, 1, 1, 0.38) if value else Color.WHITE


func is_empty_slot() -> bool:
	return item.is_empty()


func _restyle() -> void:
	if item.is_empty():
		var empty := KitStyle.empty_slot_box(self)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(state, empty)
		return
	var rarity := int(item.get("rarity", 0))
	add_theme_stylebox_override("normal", KitStyle.slot_box(self, rarity, selected))
	add_theme_stylebox_override("hover", KitStyle.slot_box(self, rarity, selected))
	add_theme_stylebox_override("pressed", KitStyle.slot_box(self, rarity, true, true))
	add_theme_stylebox_override("disabled", KitStyle.slot_box(self, rarity, selected))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
