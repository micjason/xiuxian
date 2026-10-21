class_name Toast
extends PanelContainer
## 短提示（操作结果、错误、「功能暂未开放」）。一个组件两种样子：
## - 普通提示（say / say_neutral）：深可可色胶囊 + 白字，摆在顶栏下面，几秒后淡出。
## - 「功能暂未开放」（say_locked）：美术提示条 toast_bg（SPEC_Q 12.1）：奶白胶囊、可可描边、Bold 34 #4A3A33，
##   水平居中、中心 y≈1500（1080×2340 画布，其它高度按比例），最小宽 420、高 96；
##   淡入 0.2s（同时上浮 12px）→ 停 1.5s → 淡出 0.3s，连续点只重置计时，不叠多条。没有切图时退回代码画的胶囊。
## 加入 LockedFeature.GROUP 组：任何地方调 LockedFeature.notify(node) 都由它显示「功能暂未开放」。不拦截点击。

const LOCKED_MIN_WIDTH := 420.0
const LOCKED_HEIGHT := 96.0
const LOCKED_CENTER_Y := 1500.0
const CANVAS_HEIGHT := 2340.0
const LOCKED_TEXT_COLOR := Color("4a3a33")

var _label: Label
var _tween: Tween
var _mode := "normal"
var _top := Rect2(24, 230, 1032, 110)  # 普通提示的位置（左、上、右边距、高），外壳 place_top 设置
var _normal_box: StyleBox
var _locked_box: StyleBox
var _locked_lock_box: StyleBox  # 带锁版 toast_bg_lock（设置弹窗的未开放入口，SPEC_Q 17.4）


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	_normal_box = QSkin.custom(Color(0.29, 0.23, 0.2, 0.94), Color(1, 1, 1, 0.85), 4, 999, 6, 40, 20)
	_locked_box = _make_locked_box()
	_locked_lock_box = _make_locked_box("toast_bg_lock", 124)
	add_theme_stylebox_override("panel", _normal_box)
	_label = UiKit.label("", UiTokens.FS_CAPTION, UiTokens.Q_WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)


static func _make_locked_box(cut: String = "toast_bg", left: int = 72) -> StyleBox:
	var tex := ArtLib.qui(cut)
	if tex == null:
		return QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 3, 36, 4, 40, 24)
	var box := StyleBoxTexture.new()
	box.texture = tex
	box.texture_margin_left = left
	box.texture_margin_top = 60
	box.texture_margin_right = 72
	box.texture_margin_bottom = 60
	# 贴图四周外扩 24（下 32）是投影：控件矩形 = 可见胶囊，投影画在外面
	box.expand_margin_left = 24
	box.expand_margin_top = 24
	box.expand_margin_right = 24
	box.expand_margin_bottom = 32
	box.content_margin_left = 40 + (left - 72)
	box.content_margin_right = 40
	box.content_margin_top = 24
	box.content_margin_bottom = 24
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return box


func _enter_tree() -> void:
	add_to_group(LockedFeature.GROUP)


## 外壳按安全区告诉普通提示摆在哪（画布坐标：左边距、上沿、右边距、高）。
func place_top(left: float, top: float, right: float, height: float) -> void:
	_top = Rect2(left, top, right, height)
	if _mode == "normal":
		_apply_normal_layout()


func _apply_normal_layout() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_left = _top.position.x
	offset_right = -_top.size.x
	offset_top = _top.position.y
	offset_bottom = _top.position.y + _top.size.y


## good=true 绿色、false 红色（错误）；neutral 用 say_neutral。
func say(text: String, good: bool = true, seconds: float = 3.2) -> void:
	_show(text, Color("b9f5df") if good else Color("ffc4c4"), seconds)


func say_neutral(text: String, seconds: float = 2.2) -> void:
	_show(text, UiTokens.Q_WHITE, seconds)


## LockedFeature.notify 的接收端：美术提示条。
func say_locked(feature: String = "", with_lock: bool = false) -> void:
	set_meta("last_locked_feature", feature)
	if _tween != null:
		_tween.kill()
	_mode = "locked"
	add_theme_stylebox_override("panel", _locked_lock_box if with_lock else _locked_box)
	_label.text = LockedFeature.TEXT
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.add_theme_font_override("font", ArtLib.bold_font())
	_label.add_theme_font_size_override("font_size", 34)
	_label.add_theme_color_override("font_color", LOCKED_TEXT_COLOR)
	var text_width := _label.get_theme_font("font").get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	var width := maxf(LOCKED_MIN_WIDTH, ceilf(text_width) + 80.0 + (52.0 if with_lock else 0.0))
	var view_h := get_viewport_rect().size.y if is_inside_tree() else CANVAS_HEIGHT
	var center_y := LOCKED_CENTER_Y * view_h / CANVAS_HEIGHT
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -width / 2.0
	offset_right = width / 2.0
	var top := center_y - LOCKED_HEIGHT / 2.0
	offset_top = top + 12.0
	offset_bottom = top + 12.0 + LOCKED_HEIGHT
	modulate = Color(1, 1, 1, 0)
	visible = true
	_tween = create_tween()
	_tween.set_parallel()
	_tween.tween_property(self, "modulate:a", 1.0, 0.2)
	_tween.tween_property(self, "offset_top", top, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "offset_bottom", top + LOCKED_HEIGHT, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_interval(1.5)
	_tween.chain().tween_property(self, "modulate:a", 0.0, 0.3)
	_tween.chain().tween_callback(func() -> void: visible = false)


func _show(text: String, color: Color, seconds: float) -> void:
	if _tween != null:
		_tween.kill()
	if _mode != "normal":
		_mode = "normal"
		add_theme_stylebox_override("panel", _normal_box)
		_label.remove_theme_font_override("font")
		_label.add_theme_font_size_override("font_size", UiTokens.FS_CAPTION)
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_normal_layout()
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


## 当前样子：normal（普通提示）/ locked（「功能暂未开放」提示条）。
func mode() -> String:
	return _mode


func uses_strip_art() -> bool:
	return _locked_box is StyleBoxTexture
