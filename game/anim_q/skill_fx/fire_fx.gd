extends Node2D
## 火 · 中心短爆 + 向上短火柱 + 火星；地面焦痕小
## 主 #FF9F43 / 辅 #FF5A5F；亮芯 #FFF2C8。赤炎章默认 heavy。
## 约 0.7s。

signal finished

const DURATION := 0.70
const PRIMARY := Color("FF9F43")
const SECONDARY := Color("FF5A5F")
const CORE_HOT := Color("FFF2C8")

@export var primary_color := PRIMARY
@export var secondary_color := SECONDARY
@export var fx_scale := 1.0
@export var target_offset := Vector2.ZERO
@export var autoplay := false
## 赤炎等红底章节建议 true：更大爆点、更亮芯、火柱略抬、additive 更强
@export var heavy := true

var _playing := false
var _t := 0.0

@onready var _root: Node2D = $Root
@onready var _burst: Sprite2D = $Root/Burst
@onready var _core: Sprite2D = $Root/BurstCore
@onready var _flame_a: Sprite2D = $Root/FlameA
@onready var _flame_b: Sprite2D = $Root/FlameB
@onready var _scorch: Sprite2D = $Root/Scorch
@onready var _glow: Sprite2D = $Root/Glow
@onready var _embers: CPUParticles2D = $Root/Embers
@onready var _sparks: CPUParticles2D = $Root/Sparks


func _ready() -> void:
	_apply_exports()
	_reset()
	if autoplay:
		play()


func _apply_exports() -> void:
	if _root == null:
		return
	var mul := 1.18 if heavy else 1.0
	_root.position = target_offset
	_root.scale = Vector2(fx_scale * mul, fx_scale * mul)
	_set_rgb(_burst, primary_color)
	_set_rgb(_core, CORE_HOT)
	_set_rgb(_flame_a, primary_color)
	_set_rgb(_flame_b, secondary_color.lerp(primary_color, 0.35))
	_set_rgb(_scorch, secondary_color)
	_set_rgb(_glow, CORE_HOT)
	_embers.color = primary_color.lerp(CORE_HOT, 0.25)
	_sparks.color = CORE_HOT.lerp(secondary_color, 0.2)


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
	_embers.restart()
	_embers.emitting = true
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
	for s in [_burst, _core, _flame_a, _flame_b, _scorch, _glow]:
		s.modulate.a = 0.0
	_burst.scale = Vector2(0.4, 0.4)
	_core.scale = Vector2(0.28, 0.28)
	_flame_a.scale = Vector2(0.6, 0.5)
	_flame_b.scale = Vector2(0.45, 0.4)
	_flame_a.position = Vector2(-20, -75)
	_flame_b.position = Vector2(24, -60)
	_scorch.scale = Vector2(0.28, 0.2)
	_glow.scale = Vector2(0.55, 0.55)
	_embers.emitting = false
	_sparks.emitting = false


func _process(delta: float) -> void:
	if not _playing:
		return
	_t += delta
	var heavy_boost := 1.2 if heavy else 1.0
	var bu := clampf(_t / 0.22, 0.0, 1.0)
	var ba := 1.0
	if _t < 0.035:
		ba = _t / 0.035
	elif _t > 0.28:
		ba = clampf(1.0 - (_t - 0.28) / 0.32, 0.0, 1.0)

	# larger / brighter burst + hot core
	_burst.modulate.a = ba
	_burst.scale = Vector2.ONE * lerpf(0.45, 1.75 * heavy_boost, _eo(bu))
	_burst.rotation = _t * 0.75
	_core.modulate.a = ba * (1.0 if heavy else 0.9)
	_core.scale = Vector2.ONE * lerpf(0.3, 1.25 * heavy_boost, _eo(bu))
	_glow.modulate.a = ba * (0.95 if heavy else 0.75)
	_glow.scale = Vector2.ONE * lerpf(0.8, 2.55 * heavy_boost, _eo(bu))

	# short pillars with raised additive (higher alpha)
	var fu := clampf((_t - 0.02) / 0.28, 0.0, 1.0)
	var fa := ba * (1.0 if heavy else 0.9)
	_flame_a.modulate.a = fa
	_flame_a.scale = Vector2(lerpf(0.55, 1.3 * heavy_boost, _eo(fu)), lerpf(0.45, 1.4 * heavy_boost, _eo(fu)))
	_flame_a.position.y = lerpf(-45, -125 * (1.05 if heavy else 1.0), _eo(fu))
	_flame_b.modulate.a = fa * 0.9
	_flame_b.scale = Vector2(lerpf(0.4, 1.05 * heavy_boost, _eo(fu)), lerpf(0.35, 1.2 * heavy_boost, _eo(fu)))
	_flame_b.position.y = lerpf(-35, -105 * (1.05 if heavy else 1.0), _eo(fu))

	var ru := clampf((_t - 0.04) / 0.35, 0.0, 1.0)
	var ra := 1.0
	if _t > 0.32:
		ra = clampf(1.0 - (_t - 0.32) / 0.38, 0.0, 1.0)
	_scorch.modulate.a = ra * 0.55 * clampf(ru * 2.0, 0.0, 1.0)
	_scorch.scale = Vector2(lerpf(0.22, 0.72, _eo(ru)), lerpf(0.16, 0.42, _eo(ru)))

	if _t > 0.32 and _embers.emitting:
		_embers.emitting = false
	if _t > 0.18 and _sparks.emitting:
		_sparks.emitting = false

	if _t >= DURATION:
		_playing = false
		set_process(false)
		_reset()
		finished.emit()


func _eo(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)
