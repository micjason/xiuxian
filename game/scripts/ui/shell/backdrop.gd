class_name Backdrop
extends Control
## 全屏背景（Q 版）：天青色底 + 白色圆点花纹；页面有场景画时铺在顶部（等宽缩放），下沿渐隐到底色；
## 下半部分可选一块薄荷色圆角「底板」（设计稿 lower sheet），上沿跟着页面里指定的控件走（set_sheet_anchor）。
## 场景画在 res://assets/art/q/bg/：cultivate / adventure / cave（ArtLib.bg 先找 Q 版，再找旧图）。

const DOTS := "res://assets/art/q/bg/dots_tile.png"
const Q_BG := "res://assets/art/q/bg/"
## 美术下半底板 sheet_lower.png（1080x1832，上方 40px 是外发光，SPEC_Q：放在 top−40）。
const SHEET_ART := "res://assets/art/q/ui/sheet_lower.png"
const SHEET_BLEED := 40.0
## 场景画下沿渐隐高度（SPEC_Q：修炼 250，历练 132；洞府整屏不渐隐）。
const FADE_H := {"cultivate": 250.0, "home": 250.0, "adventure": 132.0}

var _front: TextureRect
var _back: TextureRect
var _fade: TextureRect
var _haze: TextureRect
var _sheet_bleed := 0.0
var _sheet: Panel
var _sheet_dots: TextureRect
var _sheet_anchor: Control
var _sheet_pad := 52.0
var _current := ""


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base := ColorRect.new()
	base.name = "Sky"
	base.color = UiTokens.Q_SKY
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	add_child(_dots_layer(0.38))
	_back = _picture()
	_front = _picture()
	add_child(_back)
	add_child(_front)
	_fade = TextureRect.new()
	_fade.name = "SceneFade"
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fade.stretch_mode = TextureRect.STRETCH_SCALE
	var grad := Gradient.new()
	grad.set_color(0, Color(UiTokens.Q_SKY, 0.0))
	grad.set_color(1, UiTokens.Q_SKY)
	grad.add_point(0.6, Color(UiTokens.Q_SKY, 0.8))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 64
	_fade.texture = tex
	var fade_art := ArtLib.has_q("bg/scene_fade_bottom.png")
	if fade_art:
		_fade.texture = load(Q_BG + "scene_fade_bottom.png")
	_fade.anchor_right = 1.0
	add_child(_fade)
	_haze = TextureRect.new()
	_haze.name = "SceneHaze"
	_haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_haze.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_haze.stretch_mode = TextureRect.STRETCH_SCALE
	_haze.anchor_right = 1.0
	_haze.offset_bottom = 360
	_haze.texture = load(Q_BG + "scene_fade_top.png") if ArtLib.has_q("bg/scene_fade_top.png") else null
	_haze.visible = false
	add_child(_haze)
	_sheet = Panel.new()
	_sheet.name = "Sheet"
	_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.anchor_right = 1.0
	_sheet.anchor_bottom = 1.0
	if ResourceLoader.exists(SHEET_ART):
		_sheet_bleed = SHEET_BLEED
		_sheet.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		var art := TextureRect.new()
		art.name = "SheetArt"
		art.texture = load(SHEET_ART)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.anchor_right = 1.0
		art.offset_bottom = 1832
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		_sheet.add_child(art)
		var below := ColorRect.new()  # 比 1832 更高的屏（平板）用同色补齐
		below.color = Color("a0d8ce")
		below.mouse_filter = Control.MOUSE_FILTER_IGNORE
		below.anchor_right = 1.0
		below.anchor_bottom = 1.0
		below.offset_top = 1832
		_sheet.add_child(below)
		_sheet.visible = false
		add_child(_sheet)
		return
	var style := StyleBoxFlat.new()
	style.bg_color = UiTokens.Q_SHEET
	style.border_color = Color(1, 1, 1, 0.75)
	style.border_width_top = 5
	style.corner_radius_top_left = 60
	style.corner_radius_top_right = 60
	style.corner_detail = 12
	style.shadow_color = Color(0.31, 0.59, 0.55, 0.18)
	style.shadow_size = 24
	style.anti_aliasing = true
	_sheet.add_theme_stylebox_override("panel", style)
	_sheet.clip_contents = true
	_sheet_dots = _dots_layer(0.32)
	_sheet.add_child(_sheet_dots)
	_sheet.visible = false
	add_child(_sheet)


func _dots_layer(alpha: float) -> TextureRect:
	var dots := TextureRect.new()
	dots.name = "Dots"
	dots.texture = load(DOTS) if ResourceLoader.exists(DOTS) else null
	dots.set_anchors_preset(Control.PRESET_FULL_RECT)
	dots.stretch_mode = TextureRect.STRETCH_TILE
	dots.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dots.modulate = Color(1, 1, 1, alpha / 0.38)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dots


func _picture() -> TextureRect:
	var node := TextureRect.new()
	node.anchor_right = 1.0
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## 切换场景画。name 为空 = 只有天青底和圆点（背包、功法页）。名字不存在时保持当前背景（ArtLib 会 push_warning）。
func show_background(name: String) -> void:
	if name == _current:
		return
	var tex: Texture2D = null
	if not name.is_empty():
		tex = ArtLib.bg(name)
		if tex == null:
			return
	_current = name
	_back.texture = _front.texture
	_back.modulate = Color.WHITE
	_front.texture = tex
	_front.modulate = Color(1, 1, 1, 0.0)
	_layout_pictures()
	var tween := create_tween()
	tween.tween_property(_front, "modulate:a", 1.0, 0.3)
	tween.tween_callback(func() -> void: _back.texture = null)


func current_background() -> String:
	return _current


## 底板上沿跟着 anchor 控件（全局 y − pad）；anchor 为 null 时不显示底板。
func set_sheet_anchor(anchor: Control, pad: float = 52.0) -> void:
	_sheet_anchor = anchor
	_sheet_pad = pad
	_sheet.visible = anchor != null
	_update_sheet()


func sheet_visible() -> bool:
	return _sheet.visible


func sheet_top() -> float:
	return _sheet.offset_top + _sheet_bleed


func _process(_delta: float) -> void:
	_update_sheet()


func _update_sheet() -> void:
	if _sheet_anchor == null or not is_instance_valid(_sheet_anchor):
		_sheet.visible = false
		return
	_sheet.visible = _sheet_anchor.is_visible_in_tree()
	var y := _sheet_anchor.get_global_rect().position.y - get_global_rect().position.y - _sheet_pad - _sheet_bleed
	if not is_equal_approx(_sheet.offset_top, y):
		_sheet.offset_top = y


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_pictures()


## 场景画等宽铺在顶部，高度按原图比例；下面 260 像素渐隐到天青底色。
func _layout_pictures() -> void:
	var w := size.x if size.x > 0.0 else UiTokens.BASE_SIZE.x
	for node in [_front, _back]:
		var tex := (node as TextureRect).texture
		var h := w * float(tex.get_height()) / float(tex.get_width()) if tex != null else 0.0
		(node as TextureRect).offset_bottom = h
	var top_tex := _front.texture if _front.texture != null else _back.texture
	var height := w * float(top_tex.get_height()) / float(top_tex.get_width()) if top_tex != null else 0.0
	_fade.visible = top_tex != null and height < size.y - 4.0
	var scene := str(ArtLib.Q_BG_ALIAS.get(_current, _current))
	var fade_h := float(FADE_H.get(scene, 250.0))
	_fade.offset_top = height - fade_h
	_fade.offset_bottom = height + 2.0
	_haze.visible = _haze.texture != null and top_tex != null and _fade.visible
	_haze.offset_bottom = 330.0 if scene == "adventure" else 360.0
