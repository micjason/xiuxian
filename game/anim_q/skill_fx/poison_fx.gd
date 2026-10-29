extends Node2D
## 毒 · 紫绿毒雾爆开 + 上升气泡
## 主 #B8FF6A / 辅 #7A4DFF。挂点：目标中心。约 0.80s。

signal finished

const DURATION := 0.80
const PRIMARY := Color("B8FF6A")
const SECONDARY := Color("7A4DFF")

@export var primary_color := PRIMARY
@export var secondary_color := SECONDARY
@export var fx_scale := 1.0
@export var target_offset := Vector2.ZERO
@export var autoplay := false

var _playing := false
var _t := 0.0

@onready var _root: Node2D = $Root
@onready var _burst: Sprite2D = $Root/Burst
@onready var _mist: Sprite2D = $Root/Mist
@onready var _mist2: Sprite2D = $Root/Mist2
@onready var _glow: Sprite2D = $Root/Glow
@onready var _bubbles: CPUParticles2D = $Root/Bubbles


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
	_set_rgb(_burst, primary_color)
	_set_rgb(_mist, secondary_color.lerp(primary_color, 0.35))
	_set_rgb(_mist2, primary_color.lerp(secondary_color, 0.4))
	_set_rgb(_glow, secondary_color)
	_bubbles.color = primary_color.lerp(Color.WHITE, 0.15)


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
	_bubbles.restart()
	_bubbles.emitting = true
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
	for s in [_burst, _mist, _mist2, _glow]:
		s.modulate.a = 0.0
	_burst.scale = Vector2(0.35, 0.35)
	_mist.scale = Vector2(0.4, 0.4)
	_mist2.scale = Vector2(0.35, 0.35)
	_mist.position = Vector2(-10, -10)
	_mist2.position = Vector2(18, 5)
	_glow.scale = Vector2(0.5, 0.5)
	_bubbles.emitting = false


func _process(delta: float) -> void:
	if not _playing:
		return
	_t += delta
	var fade := 1.0
	if _t < 0.06:
		fade = _t / 0.06
	elif _t > 0.5:
		fade = clampf(1.0 - (_t - 0.5) / 0.3, 0.0, 1.0)

	var bu := _eo(clampf(_t / 0.28, 0.0, 1.0))
	_burst.modulate.a = fade * 0.95
	_burst.scale = Vector2.ONE * lerpf(0.4, 1.55, bu)
	_burst.rotation = _t * 0.4
	_glow.modulate.a = fade * 0.55
	_glow.scale = Vector2.ONE * lerpf(0.5, 1.8, bu)

	var mu := _eo(clampf((_t - 0.04) / 0.4, 0.0, 1.0))
	_mist.modulate.a = fade * 0.9
	_mist.scale = Vector2.ONE * lerpf(0.5, 1.7, mu)
	_mist.position = Vector2(lerpf(-10, -30, mu), lerpf(-10, -55, mu))
	_mist.rotation = _t * 0.35
	_mist2.modulate.a = fade * 0.65
	_mist2.scale = Vector2.ONE * lerpf(0.35, 1.2, mu)
	_mist2.position = Vector2(lerpf(18, 40, mu), lerpf(5, -35, mu))
	_mist2.rotation = -_t * 0.4

	if _t > 0.55:
		_bubbles.emitting = false

	if _t >= DURATION:
		_playing = false
		set_process(false)
		_reset()
		finished.emit()


func _eo(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)
