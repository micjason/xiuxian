class_name QToggle
extends Button
## Q 版开关（QKit.toggle）：薄荷绿轨道 + 白色圆钮；关时灰轨道、圆钮在左。外观用美术 toggle_on/off（112x64），没有就 _draw 画，状态看 is_on。

var is_on := false


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	flat = true
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())


func set_on(value: bool) -> void:
	is_on = value
	queue_redraw()


func _draw() -> void:
	var tex := ArtLib.qui("toggle_on" if is_on else "toggle_off")
	if tex != null:
		draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)
		return
	var h := size.y
	var track := QSkin.custom(UiTokens.Q_MINT if is_on else Color("d9cfc4"), UiTokens.Q_COCOA, 4, int(h / 2.0), 0, 0, 0)
	draw_style_box(track, Rect2(Vector2.ZERO, size))
	var knob_size := h - 8.0
	var x := size.x - knob_size - 4.0 if is_on else 4.0
	var knob := QSkin.custom(Color("fff6e6"), UiTokens.Q_COCOA, 4, int(knob_size / 2.0), 3, 0, 0)
	draw_style_box(knob, Rect2(Vector2(x, 4.0), Vector2(knob_size, knob_size)))
