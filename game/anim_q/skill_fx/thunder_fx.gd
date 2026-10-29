extends Node2D
## 雷 · 1 主落雷 + 1～2 枝叉（别太密）+ 地面小圆闪
## 主 #E8D6FF / 辅 #7B4DFF。挂点：天顶→脚底。约 0.75s。

signal finished

const DURATION := 0.75
const PRIMARY := Color("E8D6FF")
const SECONDARY := Color("7B4DFF")

@export var primary_color := PRIMARY
@export var secondary_color := SECONDARY
@export var fx_scale := 1.0
@export var target_offset := Vector2.ZERO
@export var autoplay := false
@export var bolt_height := 340.0

var _playing := false
var _t := 0.0
var _rng := RandomNumberGenerator.new()

@onready var _root: Node2D = $Root
@onready var _bolts: Array[Sprite2D] = []
@onready var _impact: Sprite2D = $Root/Impact
@onready var _glow: Sprite2D = $Root/Glow
@onready var _ring: Sprite2D = $Root/Ring
@onready var _sparks: CPUParticles2D = $Root/Sparks
@onready var _flash: ColorRect = $Flash


func _ready() -> void:
	_rng.randomize()
	for i in 3:
		_bolts.append($Root.get_node("Bolt%d" % i) as Sprite2D)
	_apply_exports()
	_reset()
	if autoplay:
		play()


func _apply_exports() -> void:
	if _root == null:
		return
	_root.position = target_offset
	_root.scale = Vector2(fx_scale, fx_scale)
	_set_rgb(_bolts[0], primary_color)  # main core
	_set_rgb(_bolts[1], secondary_color)
	_set_rgb(_bolts[2], secondary_color.lerp(primary_color, 0.4))
	_set_rgb(_impact, primary_color)
	_set_rgb(_glow, secondary_color)
	_set_rgb(_ring, secondary_color)
	_sparks.color = primary_color
	if _flash:
		_flash.color = Color(secondary_color.r, secondary_color.g, secondary_color.b, 0.0)


func _set_rgb(s: Sprite2D, c: Color) -> void:
	s.modulate = Color(c.r, c.g, c.b, s.modulate.a)


func play(at: Vector2 = Vector2.INF) -> void:
	if not is_node_ready():
		call_deferred("play", at)
		return
	if at != Vector2.INF:
		position = at
	_apply_exports()
	_playing = true
	_t = 0.0
	_reset()
	# main bolt centered; 2 thin branches offset
	_bolts[0].position = Vector2(0, -bolt_height * 0.42)
	_bolts[0].scale = Vector2(1.35, bolt_height / 300.0)
	_bolts[0].rotation = _rng.randf_range(-0.04, 0.04)
	_bolts[1].position = Vector2(-42, -bolt_height * 0.38)
	_bolts[1].scale = Vector2(0.55, bolt_height / 300.0 * 0.7)
	_bolts[1].rotation = -0.18
	_bolts[2].position = Vector2(48, -bolt_height * 0.35)
	_bolts[2].scale = Vector2(0.5, bolt_height / 300.0 * 0.55)
	_bolts[2].rotation = 0.22
	for b in _bolts:
		b.visible = false
	set_process(true)


func stop() -> void:
	_playing = false
	set_process(false)
	_reset()


func is_playing() -> bool:
	return _playing


func duration() -> float:
	return DURATION


func _reset() -> void:
	if _impact == null:
		return
	for b in _bolts:
		b.modulate.a = 0.0
		b.visible = false
	_impact.modulate.a = 0.0
	_glow.modulate.a = 0.0
	_ring.modulate.a = 0.0
	_ring.scale = Vector2(0.25, 0.18)
	_impact.scale = Vector2(0.4, 0.4)
	_glow.scale = Vector2(0.6, 0.6)
	_sparks.emitting = false
	if _flash:
		_flash.color.a = 0.0


func _process(delta: float) -> void:
	if not _playing:
		return
	_t += delta

	# brief purple screen kiss
	if _flash:
		var fa := 0.0
		if _t < 0.1:
			fa = (_t / 0.1) * 0.28
		elif _t < 0.22:
			fa = (1.0 - (_t - 0.1) / 0.12) * 0.28
		elif _t > 0.24 and _t < 0.4:
			fa = (1.0 - absf(_t - 0.3) / 0.1) * 0.4
		_flash.color.a = maxf(0.0, fa)

	# main at 0.12, branches slightly after
	var starts := [0.10, 0.16, 0.20]
	var lives := [0.28, 0.20, 0.18]
	for i in 3:
		var b := _bolts[i]
		var lt: float = _t - float(starts[i])
		if lt < 0.0:
			b.visible = false
			continue
		b.visible = true
		var u := clampf(lt / float(lives[i]), 0.0, 1.0)
		var a := 1.0
		if u < 0.12:
			a = u / 0.12
		elif u > 0.5:
			a = 1.0 - (u - 0.5) / 0.5
		b.modulate.a = clampf(a, 0.0, 1.0) * (1.0 if i == 0 else 0.7)

	# small ground flash
	var hit := _t - 0.22
	if hit >= 0.0:
		var hu := clampf(hit / 0.32, 0.0, 1.0)
		var ha := 1.0
		if hu < 0.18:
			ha = hu / 0.18
		elif hu > 0.35:
			ha = 1.0 - (hu - 0.35) / 0.65
		_impact.modulate.a = clampf(ha, 0.0, 1.0)
		_impact.scale = Vector2.ONE * lerpf(0.45, 1.25, _eo(minf(hu * 2.0, 1.0)))
		_glow.modulate.a = clampf(ha, 0.0, 1.0) * 0.9
		_glow.scale = Vector2.ONE * lerpf(0.7, 1.9, _eo(minf(hu * 1.6, 1.0)))
		_ring.modulate.a = clampf(ha * (1.0 - hu * 0.6), 0.0, 1.0) * 0.75
		_ring.scale = Vector2(lerpf(0.2, 0.95, _eo(hu)), lerpf(0.14, 0.55, _eo(hu)))
		if hit < 0.02 and not _sparks.emitting:
			_sparks.restart()
			_sparks.emitting = true
	if _t > 0.45 and _sparks.emitting:
		_sparks.emitting = false

	if _t >= DURATION:
		_playing = false
		set_process(false)
		_reset()
		finished.emit()


func _eo(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)
