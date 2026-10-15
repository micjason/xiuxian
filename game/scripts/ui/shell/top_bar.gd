class_name TopBar
extends Control
## 顶部栏（按设计稿）：头像 + 境界牌（境界名、总战力）+ 修为条。只有这四样，没有灵石/丹药/强化经验胶囊。
## 点头像发 settings_pressed（致谢与版本）。高度固定 HEIGHT，加上刘海安全区。
## 战力是含装备的总战力（服务器的 power）；修为是服务器给的小数，显示时取整/缩写。

signal settings_pressed

const HEIGHT := 272

var _realm: Label
var _power: Label
var _cult_value: Label
var _cult_status: Label
var _cult_bar_host: Control
var _avatar: Button


func _init() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fade := TextureRect.new()
	fade.texture = ArtLib.ui("topbar_fade")
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", UiTokens.PAGE_MARGIN)
	margin.add_theme_constant_override("margin_right", UiTokens.PAGE_MARGIN)
	margin.add_theme_constant_override("margin_top", UiTokens.SP_2)
	margin.add_theme_constant_override("margin_bottom", UiTokens.SP_1)
	add_child(margin)
	var column := UiKit.vbox(UiTokens.SP_1)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	column.add_child(_build_identity_row())
	column.add_child(_build_cultivation_row())


func _build_identity_row() -> Control:
	var row := UiKit.hbox(0)
	row.custom_minimum_size = Vector2(0, 140)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar = Button.new()
	_avatar.name = "Avatar"
	_avatar.custom_minimum_size = Vector2(148, 148)
	_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_avatar.focus_mode = Control.FOCUS_NONE
	_avatar.tooltip_text = "致谢与版本"
	var frame := ArtLib.nine("slot_selected")
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		_avatar.add_theme_stylebox_override(state, frame if state != "focus" else StyleBoxEmpty.new())
	var face := UiKit.icon("avatar_meditate", 104, UiTokens.GOLD_HOVER)
	face.set_anchors_preset(Control.PRESET_CENTER)
	face.offset_left = -52
	face.offset_right = 52
	face.offset_top = -52
	face.offset_bottom = 52
	_avatar.add_child(face)
	_avatar.pressed.connect(func() -> void: settings_pressed.emit())
	row.add_child(_avatar)
	var plate := PanelContainer.new()
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.custom_minimum_size = Vector2(0, 124)
	plate.add_theme_stylebox_override("panel", ArtLib.nine("panel_card"))
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(plate)
	var inner := UiKit.hbox(UiTokens.SP_2)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(inner)
	var info := UiKit.vbox(0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(info)
	_realm = UiKit.label("—", UiTokens.FS_H1, UiTokens.GOLD_HOVER)
	_realm.name = "Realm"
	_realm.add_theme_font_override("font", ArtLib.title_font())
	_realm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_realm.add_theme_constant_override("outline_size", 10)
	_realm.clip_text = true
	info.add_child(_realm)
	_power = UiKit.label("战力 0", UiTokens.FS_CAPTION, UiTokens.TEXT)
	_power.name = "Power"
	info.add_child(_power)
	var seal := PanelContainer.new()
	seal.custom_minimum_size = Vector2(72, 84)
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	seal.add_theme_stylebox_override("panel", KitStyle.box(Color(0.66, 0.12, 0.08), UiTokens.GOLD, 3, 8, 4))
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var seal_text := UiKit.label("境\n界", UiTokens.FS_MICRO, Color(1.0, 0.9, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	seal_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal.add_child(seal_text)
	inner.add_child(seal)
	return row


func _build_cultivation_row() -> Control:
	var capsule := PanelContainer.new()
	capsule.name = "CultivationCapsule"
	capsule.custom_minimum_size = Vector2(0, 96)
	capsule.add_theme_stylebox_override("panel", ArtLib.nine("chip"))
	capsule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UiKit.hbox(UiTokens.SP_2)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capsule.add_child(row)
	row.add_child(UiKit.icon("res_cultivation", 48, UiTokens.JADE))
	var text := UiKit.vbox(0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.custom_minimum_size = Vector2(300, 0)
	row.add_child(text)
	text.add_child(UiKit.label("修为", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	_cult_value = UiKit.label("0 / 0", UiTokens.FS_CAPTION, UiTokens.TEXT)
	_cult_value.name = "CultivationValue"
	text.add_child(_cult_value)
	_cult_bar_host = Control.new()
	_cult_bar_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cult_bar_host.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cult_bar_host.custom_minimum_size = Vector2(0, 44)
	_cult_bar_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_cult_bar_host)
	_cult_status = UiKit.label("", UiTokens.FS_MICRO, UiTokens.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_cult_status.name = "CultivationStatus"
	_cult_status.custom_minimum_size = Vector2(190, 0)
	row.add_child(_cult_status)
	return capsule


func apply_safe_area(inset: Vector4) -> void:
	offset_top = 0.0
	offset_left = inset.x
	offset_right = -inset.z
	offset_bottom = float(HEIGHT) + inset.y
	(get_node("Margin") as MarginContainer).add_theme_constant_override("margin_top", UiTokens.SP_2 + int(inset.y))


func bind(state: Dictionary) -> void:
	_realm.text = str(state.get("realmName", "—"))
	_power.text = "战力 %s" % OfflineView.grouped(float(state.get("power", 0)))
	var breakthrough: Dictionary = state.get("breakthrough", {}) if typeof(state.get("breakthrough", null)) == TYPE_DICTIONARY else {}
	var cultivation := float(state.get("cultivation", 0))
	var cost := float(breakthrough.get("cost", 0))
	var has_next := not BagModel.plain(breakthrough.get("nextSlug", null)).is_empty()
	_cult_value.text = "%s / %s" % [OfflineView.grouped(cultivation), OfflineView.grouped(cost)] if has_next else OfflineView.grouped(cultivation)
	var ratio := clampf(cultivation / maxf(cost, 1.0), 0.0, 1.0) if has_next else 1.0
	UiKit.clear(_cult_bar_host)
	var bar := UiKit.ratio_bar(ratio, "bar_fill_gold" if ratio >= 1.0 else "bar_fill_jade", 44)
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cult_bar_host.add_child(bar)
	if not has_next:
		_cult_status.text = "已至最高境界"
	elif cultivation >= cost:
		_cult_status.text = "已满，可突破"
	else:
		_cult_status.text = "还差 %s" % OfflineView.grouped(cost - cultivation)


func power_text() -> String:
	return _power.text


func realm_text() -> String:
	return _realm.text


func cultivation_text() -> String:
	return _cult_value.text
