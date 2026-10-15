class_name GamePopup
extends Control
## 通用弹层：半透明遮罩 + 底部面板（手机上拇指够得着）。点遮罩或右上角 × 关闭。
## 内容放进 body，按钮用 set_actions。同一个弹层可以反复 open/clear，不用每次新建。
## 不叫 PopupPanel：避免和 Godot 内置的 PopupPanel 重名。美术接入见 KitStyle（Theme 类型 GamePopup / 样式 panel）。

signal closed

var title_label: Label
var body: VBoxContainer
var actions: HBoxContainer

var _panel: PanelContainer
var _scroll: ScrollContainer
var _close_on_dim := true


func _init() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 20
	var dim := ColorRect.new()
	dim.color = UiTokens.SCRIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var art := ArtLib.nine("panel_popup")
	art.expand_margin_bottom = 80.0  # 底部面板贴着屏幕下沿，把圆角和边线推到屏幕外
	art.content_margin_bottom = 80.0
	_panel.add_theme_stylebox_override("panel", KitStyle.themed(self, &"panel", &"GamePopup", art))
	add_child(_panel)
	var column := UiKit.vbox(UiTokens.SP_2)
	_panel.add_child(column)
	var head := UiKit.hbox(UiTokens.SP_2)
	column.add_child(head)
	title_label = UiKit.label("", UiTokens.FS_H1, UiTokens.GOLD)
	title_label.add_theme_font_override("font", ArtLib.title_font())
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	head.add_child(title_label)
	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(UiTokens.H_TOUCH, UiTokens.H_TOUCH)
	close.theme_type_variation = MainTheme.VAR_GHOST
	close.add_theme_font_size_override("font_size", UiTokens.FS_H1)
	close.pressed.connect(close_popup)
	head.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 360)
	column.add_child(_scroll)
	body = UiKit.vbox(UiTokens.SP_2)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(body)
	actions = UiKit.hbox(UiTokens.TAP_GAP)
	column.add_child(actions)


func _ready() -> void:
	_layout()
	get_viewport().size_changed.connect(_layout)


func _layout() -> void:
	var inset := UiSafeArea.current(get_viewport())
	_panel.offset_left = 0
	_panel.offset_right = 0
	_panel.offset_top = -inset.w
	_panel.offset_bottom = -inset.w
	# 面板最高占屏幕 90%；内容更多时 body 在面板内滚动。
	_max_scroll = maxf(240.0, get_viewport_rect().size.y * 0.94 - 300.0)


var _max_scroll := 1000.0


func open_popup(title: String) -> void:
	title_label.text = title
	_scroll.custom_minimum_size.y = 240.0
	visible = true
	move_to_front()
	await get_tree().process_frame
	fit()


## 按内容高度调整面板高度（上限见 _layout）。内容变化后可以再调用。
func fit() -> void:
	if not is_inside_tree():
		return
	_scroll.custom_minimum_size.y = clampf(body.get_combined_minimum_size().y, 240.0, _max_scroll)


func close_popup() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func clear_content() -> void:
	UiKit.clear(body)
	UiKit.clear(actions)
	_scroll.scroll_vertical = 0


## buttons: [{text, variation?, callback?, disabled?, close?}]；默认点完关闭弹层。
func set_actions(buttons: Array) -> void:
	UiKit.clear(actions)
	for spec in buttons:
		var button := UiKit.button(str(spec.get("text", "")), StringName(spec.get("variation", MainTheme.VAR_SECONDARY)))
		button.disabled = bool(spec.get("disabled", false))
		var callback: Variant = spec.get("callback", null)
		var close_after := bool(spec.get("close", true))
		button.pressed.connect(func() -> void:
			if close_after:
				close_popup()
			if callback is Callable:
				(callback as Callable).call())
		actions.add_child(button)


func _on_dim_input(event: InputEvent) -> void:
	if _close_on_dim and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		close_popup()
	elif _close_on_dim and event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		close_popup()
