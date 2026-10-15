class_name Backdrop
extends Control
## 全屏背景：水墨画 + 上下渐隐 + 飘动的云雾。按页面切换背景（淡入淡出）。
## 背景图在 res://assets/art/bg/，名字对应页面：home / stage_1..6 / character / bag / skill / login。

const MIST_SHADER := preload("res://assets/shaders/mist.gdshader")

var _front: TextureRect
var _back: TextureRect
var _current := ""


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base := ColorRect.new()
	base.color = UiTokens.BG_ABYSS
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	_back = _picture()
	_front = _picture()
	add_child(_back)
	add_child(_front)
	# 整体压暗一层，保证文字对比度。
	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.04, 0.05, 0.34)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	var mist := TextureRect.new()
	mist.texture = ArtLib.ui("mist")
	mist.set_anchors_preset(Control.PRESET_FULL_RECT)
	mist.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mist.stretch_mode = TextureRect.STRETCH_SCALE
	mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = MIST_SHADER
	material.set_shader_parameter("mist_tex", ArtLib.ui("mist"))
	mist.material = material
	add_child(mist)
	add_child(_fade("fade_top", true))
	add_child(_fade("fade_bottom", false))


func _picture() -> TextureRect:
	var node := TextureRect.new()
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


func _fade(art: String, top: bool) -> TextureRect:
	var node := TextureRect.new()
	node.texture = ArtLib.ui(art)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.anchor_left = 0.0
	node.anchor_right = 1.0
	if top:
		node.anchor_top = 0.0
		node.anchor_bottom = 0.0
		node.offset_bottom = 520.0
	else:
		node.anchor_top = 1.0
		node.anchor_bottom = 1.0
		node.offset_top = -560.0
	return node


## 切换背景。name 不存在时保持当前背景并警告（ArtLib 会 push_warning）。
func show_background(name: String) -> void:
	if name == _current:
		return
	var tex := ArtLib.bg(name)
	if tex == null:
		return
	_current = name
	_back.texture = _front.texture
	_back.modulate = Color.WHITE
	_front.texture = tex
	_front.modulate = Color(1, 1, 1, 0.0)
	var tween := create_tween()
	tween.tween_property(_front, "modulate:a", 1.0, 0.35)


func current_background() -> String:
	return _current
