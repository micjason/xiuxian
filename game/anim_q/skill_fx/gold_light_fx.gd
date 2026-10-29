extends Node2D
## 金光 · 明亮金色径向爆开（攻击增益 / 圣击）
## 主 #FFF2C8 / 辅 #FFD45C。挂点：目标中心。约 0.65s。

signal finished

const DURATION := 0.65
const PRIMARY := Color("FFF2C8")
const SECONDARY := Color("FFD45C")

@export var primary_color := PRIMARY
@export var secondary_color := SECONDARY
@export var fx_scale := 1.0
@export var target_offset := Vector2.ZERO
@export var autoplay := false

var _playing := false
var _t := 0.0

@onready var _root: Node2D = $Root
@onready var _burst: Sprite2D = $Root/Burst
@onready var _glow: Sprite2D = $Root/Glow
@onready var _ring: Sprite2D = $Root/Ring
@onready var _core: Sprite2D = $Root/Core
@onready var _sparks: CPUParticles2D = $Root/Sparks


func _ready() -> void:
	_apply_exports()
	_reset()
	if autoplay:
		play()


func _apply_exports() -> void:
	if _root == null:
		return
	_root.position = target_offset
	_root.scale = Vector2(fx_scale, fx_scale)
	_set_rgb(_burst, secondary_color)
	_set_rgb(_glow, primary_color)
	_set_rgb(_ring, secondary_color)
	_set_rgb(_core, primary_color)
	_sparks.color = primary_color


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
	_sparks.restart()
	_sparks.emitting = true
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
	if _burst == null:
		return
	for s in [_burst, _glow, _ring, _core]:
		s.modulate.a = 0.0
	_burst.scale = Vector2(0.3, 0.3)
	_glow.scale = Vector2(0.45, 0.45)
	_ring.scale = Vector2(0.25, 0.25)
	_core.scale = Vector2(0.3, 0.3)
	_sparks.emitting = false


func _process(delta: float) -> void:
	if not _playing:
		return
	_t += delta
	var fade := 1.0
	if _t < 0.03:
		fade = _t / 0.03
	elif _t > 0.35:
		fade = clampf(1.0 - (_t - 0.35) / 0.3, 0.0, 1.0)

	var u := _eo(clampf(_t / 0.28, 0.0, 1.0))
	_burst.modulate.a = fade
	_burst.scale = Vector2.ONE * lerpf(0.3, 1.55, u)
	_burst.rotation = _t * 0.5
	_glow.modulate.a = fade * 0.85
	_glow.scale = Vector2.ONE * lerpf(0.4, 2.1, u)
	_core.modulate.a = fade
	_core.scale = Vector2.ONE * lerpf(0.25, 1.1, u)

	var ru := _eo(clampf((_t - 0.02) / 0.32, 0.0, 1.0))
	_ring.modulate.a = fade * 0.8
	_ring.scale = Vector2.ONE * lerpf(0.2, 1.35, ru)
	_ring.rotation = _t * 0.8

	if _t > 0.22 and _sparks.emitting:
		_sparks.emitting = false

	if _t >= DURATION:
		_playing = false
		set_process(false)
		_reset()
		finished.emit()


func _eo(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)
