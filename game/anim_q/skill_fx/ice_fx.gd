extends Node2D
## 冰 · 霜晶碎片飞溅 + 淡蓝白闪光 + 地面短霜环
## 主 #D6F3FF / 辅 #7EC8FF。挂点：目标中心。约 0.70s。

signal finished

const DURATION := 0.70
const PRIMARY := Color("D6F3FF")
const SECONDARY := Color("7EC8FF")

@export var primary_color := PRIMARY
@export var secondary_color := SECONDARY
@export var fx_scale := 1.0
@export var target_offset := Vector2.ZERO
@export var autoplay := false

var _playing := false
var _t := 0.0

@onready var _root: Node2D = $Root
@onready var _flash: Sprite2D = $Root/Flash
@onready var _burst: Sprite2D = $Root/Burst
@onready var _shard0: Sprite2D = $Root/Shard0
@onready var _shard1: Sprite2D = $Root/Shard1
@onready var _shard2: Sprite2D = $Root/Shard2
@onready var _frost: Sprite2D = $Root/Frost
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
	_set_rgb(_flash, primary_color)
	_set_rgb(_burst, primary_color.lerp(Color.WHITE, 0.35))
	_set_rgb(_shard0, primary_color)
	_set_rgb(_shard1, secondary_color)
	_set_rgb(_shard2, primary_color.lerp(secondary_color, 0.5))
	_set_rgb(_frost, secondary_color)
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
	if _flash == null:
		return
	for s in [_flash, _burst, _shard0, _shard1, _shard2, _frost]:
		s.modulate.a = 0.0
	_flash.scale = Vector2(0.4, 0.4)
	_burst.scale = Vector2(0.35, 0.35)
	_shard0.position = Vector2(0, -10)
	_shard1.position = Vector2(-20, 0)
	_shard2.position = Vector2(22, 5)
	_shard0.rotation = -0.2
	_shard1.rotation = 0.4
	_shard2.rotation = -0.55
	_shard0.scale = Vector2(0.45, 0.45)
	_shard1.scale = Vector2(0.35, 0.35)
	_shard2.scale = Vector2(0.3, 0.3)
	_frost.scale = Vector2(0.25, 0.18)
	_sparks.emitting = false


func _process(delta: float) -> void:
	if not _playing:
		return
	_t += delta
	var fade := 1.0
	if _t < 0.04:
		fade = _t / 0.04
	elif _t > 0.42:
		fade = clampf(1.0 - (_t - 0.42) / 0.28, 0.0, 1.0)

	var fl := 0.0
	if _t < 0.18:
		fl = clampf(_t / 0.05, 0.0, 1.0) * clampf(1.0 - (_t - 0.05) / 0.13, 0.0, 1.0)
	_flash.modulate.a = fl * 1.0
	_flash.scale = Vector2.ONE * lerpf(0.35, 1.15, fl)
	_burst.modulate.a = fl * 0.7
	_burst.scale = Vector2.ONE * lerpf(0.3, 1.4, _eo(clampf(_t / 0.22, 0.0, 1.0)))

	var u := _eo(clampf((_t - 0.02) / 0.35, 0.0, 1.0))
	_shard0.position = Vector2(lerpf(0, 55, u), lerpf(-10, -95, u))
	_shard0.rotation = lerpf(-0.2, 0.8, u)
	_shard0.scale = Vector2.ONE * lerpf(0.55, 1.25, u)
	_shard0.modulate.a = fade * clampf(u * 3.0, 0.0, 1.0)

	_shard1.position = Vector2(lerpf(-15, -90, u), lerpf(0, -40, u))
	_shard1.rotation = lerpf(0.4, -0.9, u)
	_shard1.scale = Vector2.ONE * lerpf(0.45, 1.0, u)
	_shard1.modulate.a = fade * 0.85 * clampf(u * 3.0, 0.0, 1.0)

	_shard2.position = Vector2(lerpf(18, 95, u), lerpf(5, -25, u))
	_shard2.rotation = lerpf(-0.55, 1.1, u)
	_shard2.scale = Vector2.ONE * lerpf(0.4, 0.95, u)
	_shard2.modulate.a = fade * 0.8 * clampf(u * 3.0, 0.0, 1.0)

	var ru := _eo(clampf((_t - 0.05) / 0.3, 0.0, 1.0))
	var ra := fade
	if _t > 0.38:
		ra = clampf(1.0 - (_t - 0.38) / 0.32, 0.0, 1.0)
	_frost.modulate.a = ra * 0.9 * clampf(ru * 2.0, 0.0, 1.0)
	_frost.scale = Vector2(lerpf(0.3, 1.15, ru), lerpf(0.2, 0.7, ru))

	if _t > 0.28 and _sparks.emitting:
		_sparks.emitting = false

	if _t >= DURATION:
		_playing = false
		set_process(false)
		_reset()
		finished.emit()


func _eo(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)
