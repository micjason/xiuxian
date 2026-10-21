class_name QToggleSwitch
extends Button
## 设置弹窗的音乐 / 音效开关（SPEC_Q 17.4）：整张换图 toggle_switch_on / _off（156×80，开 / 关字已烘焙）；
## 没有切图时退回 QToggle 的画法。点击切换并发 toggled_on(新状态)。

signal toggled_on(on: bool)

var is_on := false


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	flat = true
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	pressed.connect(func() -> void:
		set_on(not is_on)
		toggled_on.emit(is_on))


func set_on(value: bool) -> void:
	is_on = value
	queue_redraw()


func _draw() -> void:
	var tex := ArtLib.qui("toggle_switch_on" if is_on else "toggle_switch_off")
	if tex != null:
		draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)
		return
	var h := size.y
	var track := QSkin.custom(UiTokens.Q_MINT if is_on else Color("d9cfc4"), UiTokens.Q_COCOA, 4, int(h / 2.0), 0, 0, 0)
	draw_style_box(track, Rect2(Vector2.ZERO, size))
	var knob_size := h - 8.0
	var x := size.x - knob_size - 4.0 if is_on else 4.0
	draw_style_box(QSkin.custom(Color("fff6e6"), UiTokens.Q_COCOA, 4, int(knob_size / 2.0), 3, 0, 0), Rect2(Vector2(x, 4.0), Vector2(knob_size, knob_size)))
