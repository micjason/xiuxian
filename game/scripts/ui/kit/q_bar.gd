class_name QBar
extends Control
## Q 版进度条（QKit.bar）：优先用美术切图（bar_bg_<高> 轨道 + bar_fill_<色>_<高> 填充，只横向拉伸），
## 没有对应高度的切图就 _draw 画（轨道 + 填充 + 高光 + 分段线）。随宽度自适应。

## 轨道高度 → [轨道切图, 填充高度, 填充切图后缀]
const CUTS := {52: ["bar_bg_xiuwei_52", 44], 40: ["bar_bg_40", 32], 30: ["bar_bg_30", 22]}

var ratio := 0.0
var fill := UiTokens.Q_MINT
var track := UiTokens.Q_TRACK
var segments := 1
var fill_cut := ""
var _track_box: StyleBox
var _fill_box: StyleBox


func setup(value: float, fill_color: Color, segment_count: int = 1, track_color: Color = UiTokens.Q_TRACK, cut_color: String = "") -> void:
	ratio = clampf(value, 0.0, 1.0)
	fill = fill_color
	segments = maxi(1, segment_count)
	track = track_color
	fill_cut = cut_color
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track_box = null
	_fill_box = null
	queue_redraw()


func set_ratio(value: float) -> void:
	ratio = clampf(value, 0.0, 1.0)
	queue_redraw()


func fill_width() -> float:
	return maxf(0.0, (size.x - 8.0) * ratio)


## 用的是不是美术切图（测试用）。
func uses_cut() -> bool:
	_resolve()
	return _fill_box is StyleBoxTexture


func _color_name() -> String:
	if not fill_cut.is_empty():
		return fill_cut
	var table := {"mint": UiTokens.Q_MINT, "gold": UiTokens.Q_GOLD, "red": UiTokens.Q_RED, "blue": UiTokens.Q_BLUE}
	var best := "mint"
	var dist := 99.0
	for key in table:
		var c: Color = table[key]
		var d := absf(c.r - fill.r) + absf(c.g - fill.g) + absf(c.b - fill.b)
		if d < dist:
			dist = d
			best = key
	return best


func _resolve() -> void:
	if _fill_box != null:
		return
	var key := int(custom_minimum_size.y)
	if CUTS.has(key):
		var entry: Array = CUTS[key]
		var fill_name := "bar_fill_xiuwei_44" if key == 52 and _color_name() in ["xiuwei", "mint"] else "bar_fill_%s_%d" % [_color_name(), int(entry[1])]
		if key == 52 and fill_name != "bar_fill_xiuwei_44":
			fill_name = "bar_fill_%s_32" % _color_name()
		if ArtLib.qui(str(entry[0])) != null and ArtLib.qui(fill_name) != null:
			_track_box = ArtLib.q_nine(str(entry[0]))
			_fill_box = ArtLib.q_nine(fill_name)
			return
	_track_box = QSkin.custom(track, UiTokens.Q_COCOA, 4, int(size.y / 2.0), 0, 0, 0)
	_fill_box = QSkin.custom(fill, Color(0, 0, 0, 0), 0, 99, 0, 0, 0)


func _draw() -> void:
	_resolve()
	var h := size.y
	draw_style_box(_track_box, Rect2(Vector2.ZERO, size))
	var w := fill_width()
	var textured := _fill_box is StyleBoxTexture
	if w > 1.0:
		var inner_h := h - 8.0
		var min_w := inner_h
		if textured:
			var tb := _fill_box as StyleBoxTexture
			inner_h = float(tb.texture.get_height())
			min_w = tb.texture_margin_left + tb.texture_margin_right
		var fw := minf(maxf(w, min_w), size.x - 8.0)
		var y := (h - inner_h) / 2.0
		draw_style_box(_fill_box, Rect2(Vector2(4, y), Vector2(fw, inner_h)))
		if not textured and fw > 24.0:
			var shine := QSkin.custom(Color(1, 1, 1, 0.5), Color(0, 0, 0, 0), 0, 4, 0, 0, 0)
			draw_style_box(shine, Rect2(Vector2(12, 7), Vector2(fw - 18.0, maxf(4.0, inner_h * 0.22))))
	var divider := ArtLib.qui("bar_seg_divider") if segments > 1 else null
	for k in range(1, segments):
		var x := 4.0 + (size.x - 8.0) * float(k) / float(segments)
		if divider != null:
			draw_texture_rect(divider, Rect2(Vector2(x - 2.0, 4.0), Vector2(4.0, h - 8.0)), false)
		else:
			draw_rect(Rect2(Vector2(x - 2.0, 4.0), Vector2(4.0, h - 8.0)), Color(UiTokens.Q_COCOA, 0.35))
