class_name Toast
extends PanelContainer
## 顶部下方的短提示（操作结果、错误）。几秒后自动淡出。

var _label: Label
var _tween: Tween


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", ArtLib.nine("toast"))
	_label = UiKit.label("", UiTokens.FS_CAPTION, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_label)


func say(text: String, good: bool = true, seconds: float = 3.2) -> void:
	if _tween != null:
		_tween.kill()
	if text.is_empty():
		visible = false
		return
	_label.text = text
	_label.add_theme_color_override("font_color", UiTokens.JADE if good else UiTokens.DANGER)
	modulate = Color.WHITE
	visible = true
	_tween = create_tween()
	_tween.tween_interval(seconds)
	_tween.tween_property(self, "modulate:a", 0.0, 0.4)
	_tween.tween_callback(func() -> void: visible = false)


func text() -> String:
	return _label.text if visible else ""
