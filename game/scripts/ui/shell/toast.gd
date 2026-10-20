class_name Toast
extends PanelContainer
## 短提示（操作结果、错误、「功能暂未开放」）。Q 版：深可可色胶囊 + 白字，几秒后淡出。
## 加入 LockedFeature.GROUP 组：任何地方调 LockedFeature.notify(node) 都由它显示「功能暂未开放」。

var _label: Label
var _tween: Tween


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	add_theme_stylebox_override("panel", QSkin.custom(Color(0.29, 0.23, 0.2, 0.94), Color(1, 1, 1, 0.85), 4, 999, 6, 40, 20))
	_label = UiKit.label("", UiTokens.FS_CAPTION, UiTokens.Q_WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_label)


func _enter_tree() -> void:
	add_to_group(LockedFeature.GROUP)


## good=true 绿色、false 红色（错误）；neutral 用 say_neutral。
func say(text: String, good: bool = true, seconds: float = 3.2) -> void:
	_show(text, Color("b9f5df") if good else Color("ffc4c4"), seconds)


func say_neutral(text: String, seconds: float = 2.2) -> void:
	_show(text, UiTokens.Q_WHITE, seconds)


## LockedFeature.notify 的接收端。
func say_locked(feature: String = "") -> void:
	say_neutral(LockedFeature.TEXT)
	set_meta("last_locked_feature", feature)


func _show(text: String, color: Color, seconds: float) -> void:
	if _tween != null:
		_tween.kill()
	if text.is_empty():
		visible = false
		return
	_label.text = text
	_label.add_theme_color_override("font_color", color)
	modulate = Color.WHITE
	visible = true
	_tween = create_tween()
	_tween.tween_interval(seconds)
	_tween.tween_property(self, "modulate:a", 0.0, 0.4)
	_tween.tween_callback(func() -> void: visible = false)


func text() -> String:
	return _label.text if visible else ""
