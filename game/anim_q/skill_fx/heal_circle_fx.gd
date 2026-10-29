extends Node2D
## 治疗法阵 · 脚底圆环（青主 + 浅金描边）+ 柔和上升粒子
## 主 #5EE1C5 / 辅 #FFE27A。约 1.0s。攻击法阵可换 primary=#FFD45C secondary=#5AAEFF。

signal finished

const DURATION := 1.0
const PRIMARY := Color("5EE1C5")
const SECONDARY := Color("FFE27A")

@export var primary_color := PRIMARY
@export var secondary_color := SECONDARY
@export var fx_scale := 1.0
@export var target_offset := Vector2.ZERO
@export var autoplay := false
## true = 加短柱光（攻击法阵更「硬」时用）
@export var show_pillar := false

var _playing := false
var _t := 0.0

@onready var _root: Node2D = $Root
@onready var _ground: Node2D = $Root/Ground
@onready var _circle: Sprite2D = $Root/Ground/Circle
@onready var _ring_gold: Sprite2D = $Root/Ground/RingGold
@onready var _ring_cyan: Sprite2D = $Root/Ground/RingCyan
@onready var _glow: Sprite2D = $Root/Glow
@onready var _pillar: Sprite2D = $Root/Pillar
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
	_set_rgb(_circle, primary_color)
	_set_rgb(_ring_gold, secondary_color)
	_set_rgb(_ring_cyan, primary_color.lerp(Color.WHITE, 0.2))
	_set_rgb(_glow, primary_color)
	_set_rgb(_pillar, primary_color)
	_pillar.visible = show_pillar
	_motes.color = primary_color.lerp(Color.WHITE, 0.25)


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
	if _circle == null:
		return
	_circle.modulate.a = 0.0
	_ring_gold.modulate.a = 0.0
	_ring_cyan.modulate.a = 0.0
	_glow.modulate.a = 0.0
	_pillar.modulate.a = 0.0
	_circle.scale = Vector2(0.35, 0.35)
	_ring_gold.scale = Vector2(0.4, 0.4)
	_ring_cyan.scale = Vector2(0.3, 0.3)
	_glow.scale = Vector2(0.5, 0.35)
	_pillar.scale = Vector2(0.5, 0.6)
	_motes.emitting = false


func _process(delta: float) -> void:
	if not _playing:
		return
	_t += delta
	var a := 1.0
	if _t < 0.18:
		a = _t / 0.18
	elif _t > DURATION - 0.3:
		a = clampf((DURATION - _t) / 0.3, 0.0, 1.0)

	var pulse := 1.0 + 0.05 * sin(_t * TAU * 2.0)
	var grow := _eo(clampf(_t / 0.32, 0.0, 1.0))

	_circle.modulate.a = a * 0.8
	_circle.scale = Vector2.ONE * lerpf(0.35, 1.0, grow) * pulse
	_circle.rotation = _t * 0.3

	_ring_gold.modulate.a = a * 0.75
	_ring_gold.scale = Vector2.ONE * lerpf(0.45, 1.15, grow)
	_ring_gold.rotation = -_t * 0.4

	_ring_cyan.modulate.a = a * 0.65
	_ring_cyan.scale = Vector2.ONE * lerpf(0.3, 0.85, grow) * (1.0 + 0.04 * sin(_t * TAU * 1.7))
	_ring_cyan.rotation = _t * 0.55

	_glow.modulate.a = a * 0.4 * (0.8 + 0.2 * sin(_t * TAU * 1.5))
	_glow.scale = Vector2(lerpf(0.45, 1.2, grow), lerpf(0.3, 0.75, grow))

	if show_pillar:
		var pa := a * 0.7
		if _t < 0.25:
			pa *= _t / 0.25
		_pillar.modulate.a = pa
		_pillar.scale = Vector2(lerpf(0.35, 0.7, grow), lerpf(0.4, 1.0, grow))

	if _t > DURATION - 0.35:
		_motes.emitting = false

	if _t >= DURATION:
		_playing = false
		set_process(false)
		_reset()
		finished.emit()


func _eo(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)
