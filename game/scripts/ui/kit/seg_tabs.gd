class_name SegTabs
extends HBoxContainer
## 分段页签（分类用）。等宽、每个至少 128 像素高。
## set_tabs([{id, name, badge?}])，select(id)，点击发 tab_changed(id)。
## 不叫 TabBar：避免和 Godot 内置的 TabBar 控件重名。

signal tab_changed(tab_id: String)

var current := ""
var _buttons: Dictionary = {}
var _titles: Dictionary = {}


func _init() -> void:
	add_theme_constant_override("separation", UiTokens.TAP_GAP)


func set_tabs(tabs: Array, selected: String = "") -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()
	_titles.clear()
	for tab in tabs:
		var id := str(tab.get("id", ""))
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, UiTokens.H_TOUCH)
		button.add_theme_font_size_override("font_size", UiTokens.FS_BODY)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(select.bind(id, true))
		add_child(button)
		_buttons[id] = button
		_titles[id] = str(tab.get("name", id))
		set_badge(id, str(tab.get("badge", "")))
	current = selected if _buttons.has(selected) else (str(tabs[0].get("id", "")) if not tabs.is_empty() else "")
	_refresh()


func set_badge(id: String, badge: String) -> void:
	if not _buttons.has(id):
		return
	(_buttons[id] as Button).text = str(_titles[id]) + ((" %s" % badge) if not badge.is_empty() else "")


func select(id: String, emit: bool = false) -> void:
	if not _buttons.has(id):
		return
	var changed := id != current
	current = id
	_refresh()
	if emit and changed:
		tab_changed.emit(id)


func _refresh() -> void:
	for id in _buttons:
		(_buttons[id] as Button).theme_type_variation = MainTheme.VAR_CHOICE_SELECTED if id == current else MainTheme.VAR_CHOICE
