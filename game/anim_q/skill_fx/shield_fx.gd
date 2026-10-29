extends Node2D
## 护盾 · 青金短时穹顶/气泡（己方自身）
## 主 #A8E8E0 / 辅 #FFD45C。挂点：自身中心，target_offset≈0。约 0.90s。

signal finished

const DURATION := 0.90
const PRIMARY := Color("A8E8E0")
const SECONDARY := Color("FFD45C")

@export var primary_color := PRIMARY
@export var secondary_color := SECONDARY
@export var fx_scale := 1.0
@export var target_offset := Vector2.ZERO
@export var autoplay := false

var _playing := false
var _t := 0.0

@onready var _root: Node2D = $Root
@onready var _dome: Sprite2D = $Root/Dome
@onready var _ring: Sprite2D = $Root/Ring
@onready var _glow: Sprite2D = $Root/Glow
@onready var _flash: Sprite2D = $Root/Flash
@onready var _motes: CPUParticles2D = $Root/Motes


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
	_set_rgb(_dome, primary_color)
	_set_rgb(_ring, secondary_color)
	_set_rgb(_glow, primary_color.lerp(Color.WHITE, 0.25))
	_set_rgb(_flash, secondary_color)
	_motes.color = secondary_color.lerp(primary_color, 0.4)


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
	_motes.restart()
	_motes.emitting = true
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
	if _dome == null:
		return
	for s in [_dome, _ring, _glow, _flash]:
		s.modulate.a = 0.0
	_dome.scale = Vector2(0.35, 0.35)
	_ring.scale = Vector2(0.3, 0.3)
	_glow.scale = Vector2(0.4, 0.4)
	_flash.scale = Vector2(0.3, 0.3)
	_motes.emitting = false


func _process(delta: float) -> void:
	if not _playing:
		return
	_t += delta
	var fade := 1.0
	if _t < 0.12:
		fade = _t / 0.12
	elif _t > DURATION - 0.28:
		fade = clampf((DURATION - _t) / 0.28, 0.0, 1.0)

	var grow := _eo(clampf(_t / 0.28, 0.0, 1.0))
	var pulse := 1.0 + 0.04 * sin(_t * TAU * 2.2)

	_dome.modulate.a = fade * 0.95
	_dome.scale = Vector2.ONE * lerpf(0.4, 1.2, grow) * pulse
	_glow.modulate.a = fade * 0.45 * (0.85 + 0.15 * sin(_t * TAU * 1.8))
	_glow.scale = Vector2.ONE * lerpf(0.4, 1.35, grow)

	_ring.modulate.a = fade * 0.7
	_ring.scale = Vector2.ONE * lerpf(0.3, 1.15, grow)
	_ring.rotation = _t * 0.55

	var fl := 0.0
	if _t < 0.2:
		fl = clampf(_t / 0.06, 0.0, 1.0) * clampf(1.0 - (_t - 0.06) / 0.14, 0.0, 1.0)
	_flash.modulate.a = fl * 0.65
	_flash.scale = Vector2.ONE * lerpf(0.3, 1.0, fl)

	if _t > DURATION - 0.35:
		_motes.emitting = false

	if _t >= DURATION:
		_playing = false
		set_process(false)
		_reset()
		finished.emit()


func _eo(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)
