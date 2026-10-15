class_name TopBar
extends Control
## 顶部栏：头像框 + 境界名 + 战力；右侧资源胶囊（修为、强化经验）和设置入口（致谢/版本）。
## 高度固定 HEIGHT，加上刘海安全区。点设置发 settings_pressed。

signal settings_pressed

const HEIGHT := 184

var _realm: Label
var _power: Label
var _cult: PanelContainer
var _enhance: PanelContainer
var _settings: Button


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
	var row := UiKit.hbox(UiTokens.SP_2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(136, 136)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar.add_theme_stylebox_override("panel", ArtLib.nine("slot_selected"))
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.add_child(UiKit.icon("avatar_meditate", 96, UiTokens.GOLD_HOVER))
	row.add_child(avatar)
	var info := UiKit.vbox(0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	_realm = UiKit.label("—", UiTokens.FS_H1, UiTokens.TEXT)
	_realm.add_theme_font_override("font", ArtLib.title_font())
	_realm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_realm.add_theme_constant_override("outline_size", 10)
	_realm.clip_text = true
	info.add_child(_realm)
	var power_row := UiKit.hbox(8)
	power_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	power_row.add_child(UiKit.icon("res_power", 44, UiTokens.GOLD))
	_power = UiKit.label("战力 0", UiTokens.FS_BODY, UiTokens.GOLD)
	_power.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_power.add_theme_constant_override("outline_size", 8)
	power_row.add_child(_power)
	info.add_child(power_row)
	var chips := UiKit.vbox(6)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chips)
	_cult = UiKit.chip("res_cultivation", "修为 0", UiTokens.JADE)
	_enhance = UiKit.chip("res_enhance", "强化 0", UiTokens.GOLD)
	chips.add_child(_cult)
	chips.add_child(_enhance)
	_settings = Button.new()
	_settings.theme_type_variation = MainTheme.VAR_GHOST
	_settings.custom_minimum_size = Vector2(UiTokens.H_TOUCH - 20, UiTokens.H_TOUCH - 20)
	_settings.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_settings.focus_mode = Control.FOCUS_NONE
	_settings.tooltip_text = "致谢与版本"
	var gear := UiKit.icon("ui_settings", 64, UiTokens.TEXT_MUTED)
	gear.set_anchors_preset(Control.PRESET_CENTER)
	gear.offset_left = -32
	gear.offset_right = 32
	gear.offset_top = -32
	gear.offset_bottom = 32
	_settings.add_child(gear)
	_settings.pressed.connect(func() -> void: settings_pressed.emit())
	row.add_child(_settings)


func apply_safe_area(inset: Vector4) -> void:
	offset_top = 0.0
	offset_left = inset.x
	offset_right = -inset.z
	offset_bottom = float(HEIGHT) + inset.y
	(get_node("Margin") as MarginContainer).add_theme_constant_override("margin_top", UiTokens.SP_2 + int(inset.y))


func bind(state: Dictionary) -> void:
	_realm.text = str(state.get("realmName", "—"))
	_power.text = "战力 %d" % int(state.get("power", 0))
	(_cult.find_child("Text", true, false) as Label).text = "修为 %s" % CultivationFormat.amount(float(state.get("cultivation", 0)))
	(_enhance.find_child("Text", true, false) as Label).text = "强化 %d" % int(state.get("enhanceExp", 0))


func power_text() -> String:
	return _power.text
