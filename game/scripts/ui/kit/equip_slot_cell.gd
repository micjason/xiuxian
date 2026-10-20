class_name EquipSlotCell
extends Button
## 装备栏里的一个部位格：部位名 + 图标位 + 装备名。三种状态：已穿戴、空（可穿戴）、锁定/未开放。
## 数据来自 SlotConfig 的部位字典 + EquipModel 给出的物品展示字典（空部位传 {}）。
## 最小 208×224 画布像素，整格可点。点击发 slot_pressed(slot_id)。

signal slot_pressed(slot_id: String)

var slot: Dictionary = {}
var item: Dictionary = {}

var _name_label: Label
var _icon: TextureRect
var _glow: TextureRect
var _glyph: Label
var _item_label: Label
var _badge: Label
## Q 版外观（背包纸娃娃）：品质格切图 slot_<品质>，部位名不在格子里（背包页在格子下面放标签）。
var q_mode := false


func _init() -> void:
	custom_minimum_size = Vector2(208, 232)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_NONE
	text = ""
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 10
	column.offset_right = -10
	column.offset_top = 10
	column.offset_bottom = -10
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_name_label = UiKit.label("", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_name_label)
	var icon_box := Control.new()
	icon_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(icon_box)
	_glow = TextureRect.new()
	_glow.texture = ArtLib.ui("glow_soft")
	_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(_glow)
	_icon = TextureRect.new()
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = 18
	_icon.offset_right = -18
	_icon.offset_top = 4
	_icon.offset_bottom = -4
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(_icon)
	_glyph = UiKit.label("", UiTokens.FS_H1, UiTokens.TEXT_DISABLED, HORIZONTAL_ALIGNMENT_CENTER)
	_glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_box.add_child(_glyph)
	_badge = UiKit.label("", UiTokens.FS_MICRO, UiTokens.GOLD_HOVER, HORIZONTAL_ALIGNMENT_RIGHT)
	_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_badge.offset_left = -100
	_badge.offset_right = -2
	_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_badge.add_theme_constant_override("outline_size", 8)
	icon_box.add_child(_badge)
	_item_label = UiKit.label("", UiTokens.FS_MICRO, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_item_label.clip_text = true
	_item_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_item_label)
	pressed.connect(func() -> void: slot_pressed.emit(str(slot.get("id", ""))))


## Q 版纸娃娃格（设计稿 150 方格）：品质框用美术 slot_* 切图，隐藏格内的部位名和装备名，角标「+N」白字描边。
func make_q(size: float = 150.0) -> void:
	q_mode = true
	custom_minimum_size = Vector2(size, size * 166.0 / 160.0)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_name_label.visible = false
	_item_label.visible = false
	var column := _icon.get_parent().get_parent() as Control
	column.offset_left = size * 0.1
	column.offset_right = -size * 0.1
	column.offset_top = size * 0.1
	column.offset_bottom = -size * 0.14
	_icon.offset_left = 0
	_icon.offset_right = 0
	_icon.offset_top = 0
	_icon.offset_bottom = 0
	_badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_badge.offset_left = -size * 0.06
	_badge.offset_top = -size * 0.08
	_badge.offset_right = 90
	_badge.offset_bottom = 40
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_badge.add_theme_font_override("font", ArtLib.title_font())
	_badge.add_theme_color_override("font_color", UiTokens.Q_WHITE)
	_badge.add_theme_color_override("font_outline_color", UiTokens.Q_COCOA)
	_badge.add_theme_constant_override("outline_size", 9)


## 紧凑模式（背包页一行放 8 格）：缩小最小尺寸，隐藏下面的装备名（名字看详情）。
func make_compact(width: float = 112.0, height: float = 150.0) -> void:
	custom_minimum_size = Vector2(width, height)
	_item_label.visible = false


func setup(slot_data: Dictionary, item_data: Dictionary) -> void:
	slot = slot_data
	item = item_data
	_name_label.text = str(slot.get("name", ""))
	var locked := bool(slot.get("locked", false))
	var unsupported := not bool(slot.get("supported", false)) and not locked
	disabled = false
	_badge.text = ""
	_glow.visible = false
	if locked or unsupported:
		_set_icon(ArtLib.icon("ui_lock"), Color(UiTokens.TEXT_DISABLED, 0.8))
		_item_label.text = str(slot.get("note", "未开放")) if locked else "未开放"
		_item_label.add_theme_color_override("font_color", UiTokens.TEXT_DISABLED)
		_set_state("locked")
	elif item.is_empty():
		_set_icon(ArtLib.icon(ArtLib.slot_icon_name(str(slot.get("id", "")))), Color(UiTokens.TEXT_DISABLED, 0.55))
		_item_label.text = "空"
		_item_label.add_theme_color_override("font_color", UiTokens.TEXT_DISABLED)
		_set_state("empty")
	else:
		var rarity := int(item.get("rarity", 0))
		var color := UiTokens.rarity_color(rarity)
		var art := KitStyle.icon_for(item)
		_set_icon(art.get("texture", null) as Texture2D, color.lightened(0.25) if bool(art.get("tint", false)) else Color.WHITE)
		_item_label.text = str(item.get("name", ""))
		_item_label.add_theme_color_override("font_color", color.lightened(0.1))
		var enhance := int(item.get("enhance", 0))
		_badge.text = ("+%d" % enhance) if enhance > 0 else ""
		_glow.visible = KitStyle.glow_alpha(rarity) > 0.0
		_glow.modulate = Color(color, KitStyle.glow_alpha(rarity))
		_set_state("filled", rarity)


func _set_icon(tex: Texture2D, tint: Color) -> void:
	_icon.texture = tex
	_icon.modulate = tint
	_icon.visible = tex != null
	_glyph.text = "" if tex != null else str(slot.get("glyph", ""))


func _set_state(state: String, rarity: int = 0) -> void:
	if q_mode:
		_glow.visible = false
		var cut := str(QKit.SLOT_CUTS[clampi(rarity, 0, 5)]) if state == "filled" else "slot_empty"
		var tex := ArtLib.qui(cut)
		if tex != null:
			var box := StyleBoxTexture.new()
			box.texture = tex
			if state == "locked":
				box.modulate_color = Color(0.85, 0.82, 0.8)
			var down := box.duplicate() as StyleBoxTexture
			down.modulate_color = Color(0.9, 0.88, 0.85)
			for name in ["normal", "hover", "disabled"]:
				add_theme_stylebox_override(name, box)
			add_theme_stylebox_override("pressed", down)
			add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			if state == "locked":
				_icon.texture = ArtLib.qui("lock") if ArtLib.qui("lock") != null else _icon.texture
				_icon.modulate = Color.WHITE
				_icon.offset_left = 12
				_icon.offset_right = -12
			elif state == "empty":
				_icon.modulate = Color(UiTokens.Q_COCOA, 0.35)
			return
	var style: StyleBox
	match state:
		"filled":
			style = KitStyle.themed(self, &"filled", &"EquipSlot", ArtLib.nine(ArtLib.slot_frame(rarity)))
		"empty":
			style = KitStyle.themed(self, &"empty", &"EquipSlot", ArtLib.nine("slot_empty"))
		_:
			style = KitStyle.locked_slot_box(self)
	for name in ["normal", "hover", "disabled"]:
		add_theme_stylebox_override(name, style)
	add_theme_stylebox_override("pressed", ArtLib.nine("slot_selected"))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
