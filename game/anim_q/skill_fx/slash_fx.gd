extends Node2D
## 斩击/刀光 · 1～2 道水平弧 + 短拖尾（银白主 / 淡青辅）
## 挂点：目标身前。时长约 0.55s。
## 伪3D P0：Arc2 = z_behind（稍暗稍大），Arc/Flash/Streak = z_front（亮、短）。见 PSEUDO3D_Z_LAYERS.md。

signal finished

const DURATION := 0.55
const PRIMARY := Color("F5FBFF")
const SECONDARY := Color("A8E8E0")

@export var primary_color := PRIMARY
@export var secondary_color := SECONDARY
@export var fx_scale := 1.0
@export var target_offset := Vector2.ZERO
@export var face := 1.0
@export var autoplay := false

var _playing := false
var _t := 0.0

@onready var _root: Node2D = $Root
@onready var _arc: Sprite2D = $Root/Arc
@onready var _arc2: Sprite2D = $Root/Arc2
@onready var _streak: Sprite2D = $Root/Streak
@onready var _flash: Sprite2D = $Root/Flash
@onready var _sparks: CPUParticles2D = $Root/Sparks


func _ready() -> void:
	_apply_exports()
	_apply_z_layers()
	_reset()
	if autoplay:
		play()


## 前后景分层：后层稍暗稍大，前层亮短。至少后1+前1。
func _apply_z_layers() -> void:
	if _arc2 == null:
		return
	_arc2.z_as_relative = true
	_arc2.z_index = -2
	_arc.z_as_relative = true
	_arc.z_index = 2
	_streak.z_as_relative = true
	_streak.z_index = 1
	_flash.z_as_relative = true
	_flash.z_index = 3
	_sparks.z_as_relative = true
	_sparks.z_index = 4


func _apply_exports() -> void:
	if _root == null:
		return
	_root.position = target_offset
	_root.scale = Vector2(fx_scale * face, fx_scale)
	_set_rgb(_arc, primary_color)
	_set_rgb(_arc2, secondary_color)
	_set_rgb(_streak, primary_color.lerp(secondary_color, 0.35))
	_set_rgb(_flash, primary_color)
	_sparks.color = secondary_color


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
	if _arc == null:
		return
	_arc.modulate.a = 0.0
	_arc2.modulate.a = 0.0
	_streak.modulate.a = 0.0
	_flash.modulate.a = 0.0
	_arc.rotation = -0.35
	_arc.scale = Vector2(0.6, 0.7)
	_arc2.rotation = -0.55
	_arc2.scale = Vector2(0.45, 0.55)
	_streak.scale = Vector2(0.35, 0.7)
	_flash.scale = Vector2(0.35, 0.35)
	_sparks.emitting = false


func _process(delta: float) -> void:
	if not _playing:
		return
	_t += delta
	var sweep := clampf((_t - 0.02) / 0.22, 0.0, 1.0)
	var fade := 1.0
	if _t > 0.32:
		fade = clampf(1.0 - (_t - 0.32) / 0.23, 0.0, 1.0)

	# z_front：亮、短刃
	_arc.rotation = lerpf(-0.4, 0.55, sweep)
	_arc.scale = Vector2(lerpf(0.55, 1.05, _eo(sweep)), lerpf(0.65, 0.95, _eo(sweep)))
	var front_a := fade * lerpf(0.0, 1.0, clampf(sweep * 2.8, 0.0, 1.0))
	_arc.modulate = Color(minf(1.0, primary_color.r * 1.2), minf(1.0, primary_color.g * 1.2), minf(1.0, primary_color.b * 1.2), front_a)

	# z_behind：稍暗、稍大（scale ×1.08～1.15 量级）
	var a2 := clampf((_t - 0.05) / 0.28, 0.0, 1.0)
	_arc2.rotation = lerpf(-0.6, 0.4, a2)
	_arc2.scale = Vector2(lerpf(0.5, 1.15, _eo(a2)), lerpf(0.55, 1.05, _eo(a2)))
	var back_a := fade * 0.55 * lerpf(0.0, 1.0, clampf(a2 * 2.2, 0.0, 1.0))
	_arc2.modulate = Color(secondary_color.r * 0.78, secondary_color.g * 0.78, secondary_color.b * 0.85, back_a)

	_streak.rotation = _arc.rotation * 0.5
	_streak.scale = Vector2(lerpf(0.3, 1.0, sweep), lerpf(0.55, 0.8, sweep))
	_streak.modulate.a = fade * 0.7 * clampf(sweep * 2.0, 0.0, 1.0)

	# 前层闪光更短更亮
	var fl := 0.0
	if _t < 0.12:
		fl = clampf(_t / 0.04, 0.0, 1.0) * clampf(1.0 - (_t - 0.04) / 0.08, 0.0, 1.0)
	_flash.modulate.a = fl * 0.9
	_flash.scale = Vector2.ONE * lerpf(0.28, 0.85, fl)

	if _t > 0.22 and _sparks.emitting:
		_sparks.emitting = false

	if _t >= DURATION:
		_playing = false
		set_process(false)
		_reset()
		finished.emit()


func _eo(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)
