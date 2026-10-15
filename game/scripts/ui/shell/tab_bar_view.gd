class_name TabBarView
extends Control
## 底部页签（本版四个：修炼 / 背包 / 功法 / 洞府）：图标 + 文字 + 红点。选中项有金色底板。点击发 page_selected(页面 id)。
## 不叫 TabBar：避免和 Godot 内置的 TabBar 控件重名。图标在 assets/art/icons/tab_*.png（白色剪影，运行时染色）。

signal page_selected(page: String)

const HEIGHT := 176

var _tabs: Array[Dictionary] = []
var _buttons: Dictionary = {}
var _dots: Dictionary = {}
var _bgs: Dictionary = {}
var _icons: Dictionary = {}
var _labels: Dictionary = {}
var current := ""


func _init() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dock := TextureRect.new()
	dock.texture = ArtLib.ui("dock_bg")
	dock.set_anchors_preset(Control.PRESET_FULL_RECT)
	dock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dock.stretch_mode = TextureRect.STRETCH_SCALE
	dock.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dock)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_top = 14
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)


## tabs: [{id, name, icon}]
func set_tabs(tabs: Array[Dictionary], selected: String) -> void:
	_tabs = tabs
	var row := get_node("Row") as HBoxContainer
	UiKit.clear(row)
	_buttons.clear()
	_dots.clear()
	_bgs.clear()
	_icons.clear()
	_labels.clear()
	for tab in tabs:
		var id := str(tab.get("id", ""))
		var button := Button.new()
		button.name = "Tab_" + id
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.flat = true
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.pressed.connect(_on_pressed.bind(id))
		row.add_child(button)
		_buttons[id] = button
		var bg := TextureRect.new()
		bg.texture = ArtLib.ui("tab_selected_bg")
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.visible = false
		button.add_child(bg)
		_bgs[id] = bg
		var column := VBoxContainer.new()
		column.set_anchors_preset(Control.PRESET_FULL_RECT)
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_theme_constant_override("separation", 0)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(column)
		var icon := UiKit.icon_from(ArtLib.icon_or(str(tab.get("icon", "")), str(tab.get("fallback", "ui_gate"))), 84, UiTokens.TEXT_MUTED)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(icon)
		_icons[id] = icon
		var label := UiKit.label(str(tab.get("name", id)), UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		column.add_child(label)
		_labels[id] = label
		var dot := UiKit.reddot()
		dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		dot.offset_left = -78
		dot.offset_right = -42
		dot.offset_top = 14
		dot.offset_bottom = 50
		dot.visible = false
		button.add_child(dot)
		_dots[id] = dot
	current = selected
	_refresh()


## 点页签：即使已在这个页签也发信号（修炼页签下的历练/首领战/突破页要靠它回到修炼主页）。
func _on_pressed(id: String) -> void:
	select(id, false)
	page_selected.emit(id)


func select(id: String, emit: bool = false) -> void:
	if not _buttons.has(id):
		return
	var changed := id != current
	current = id
	_refresh()
	if emit and changed:
		page_selected.emit(id)


func set_dot(id: String, on: bool) -> void:
	if _dots.has(id):
		(_dots[id] as CanvasItem).visible = on


func has_dot(id: String) -> bool:
	return _dots.has(id) and (_dots[id] as CanvasItem).visible


func button_of(id: String) -> Button:
	return _buttons.get(id, null)


func apply_safe_area(inset: Vector4) -> void:
	offset_left = inset.x
	offset_right = -inset.z
	offset_top = -(float(HEIGHT) + inset.w)
	offset_bottom = 0.0
	(get_node("Row") as Control).offset_bottom = -inset.w


func _refresh() -> void:
	for id in _buttons:
		var active: bool = id == current
		(_bgs[id] as CanvasItem).visible = active
		(_icons[id] as Control).modulate = UiTokens.GOLD_HOVER if active else UiTokens.TEXT_MUTED
		(_labels[id] as Label).add_theme_color_override("font_color", UiTokens.GOLD_HOVER if active else UiTokens.TEXT_MUTED)
