extends Node2D
## 洞府·药园浇水（静暖）
## play_water ≈2.4s；garden_growing 循环；crop bounce 4–8%
signal finished
signal water_done

const DUR_WATER := 2.40
const DUR_GROW := 2.80

@export var fx_scale := 1.0
@export var autoplay := false
@export var harvest_glow := true

var _mode := ""  # water | grow | ""
var _t := 0.0

@onready var _root: Node2D = $Root
@onready var _shadow: Sprite2D = $Root/Shadow
@onready var _lingpu: Sprite2D = $Root/Lingpu
@onready var _can: Sprite2D = $Root/Can
@onready var _arc: Sprite2D = $Root/WaterArc
@onready var _drops: CPUParticles2D = $Root/Drops
@onready var _dew: Sprite2D = $Root/Dew
@onready var _crop_pulse: Sprite2D = $Root/CropPulse
@onready var _harvest: Sprite2D = $Root/HarvestGlow

func _ready() -> void:
	_root.scale = Vector2(fx_scale, fx_scale)
	_reset()
	if autoplay:
		play_water()

func _reset() -> void:
	_arc.modulate.a = 0.0
	_dew.modulate.a = 0.0
	_crop_pulse.modulate.a = 0.0
	_crop_pulse.scale = Vector2.ONE
	_harvest.modulate.a = 0.0
	_can.rotation = 0.0
	_lingpu.position.y = 0.0
	_drops.emitting = false
	set_process(false)

func play_water(at: Vector2 = Vector2.INF) -> void:
	if not is_node_ready():
		call_deferred("play_water", at)
		return
	if at != Vector2.INF:
		position = at
	_mode = "water"
	_t = 0.0
	_reset()
	_drops.restart()
	set_process(true)

func play_growing(at: Vector2 = Vector2.INF) -> void:
	if not is_node_ready():
		call_deferred("play_growing", at)
		return
	if at != Vector2.INF:
		position = at
	_mode = "grow"
	_t = 0.0
	_reset()
	set_process(true)

func stop() -> void:
	_mode = ""
	_reset()

func is_playing() -> bool:
	return _mode != ""

func _process(dt: float) -> void:
	_t += dt
	if _mode == "water":
		_tick_water()
	elif _mode == "grow":
		_tick_grow()

func _tick_water() -> void:
	var u := clampf(_t / DUR_WATER, 0.0, 1.0)
	# 0-0.15 tip can; 0.15-0.75 pour; 0.55-0.95 crop bounce; end
	var tip := smoothstep(0.0, 0.18, u) * (1.0 - smoothstep(0.78, 0.95, u))
	_can.rotation = -0.55 * tip
	_lingpu.position.y = -2.0 * tip
	var pour := smoothstep(0.12, 0.22, u) * (1.0 - smoothstep(0.72, 0.88, u))
	_arc.modulate.a = pour * 0.92
	_arc.scale = Vector2(0.85 + 0.2 * pour, 0.9 + 0.15 * sin(_t * 14.0) * pour)
	_drops.emitting = pour > 0.2
	var bounce := smoothstep(0.45, 0.55, u) * (1.0 - smoothstep(0.85, 0.98, u))
	var s := 1.0 + 0.06 * sin(_t * 10.0) * bounce
	_crop_pulse.scale = Vector2(s, s)
	_crop_pulse.modulate.a = bounce * 0.55
	_dew.modulate.a = bounce * 0.85
	_dew.position.y = -4.0 * bounce
	if harvest_glow:
		_harvest.modulate.a = 0.35 + 0.25 * sin(_t * 3.0)
	if u >= 1.0:
		_mode = ""
		_reset()
		water_done.emit()
		finished.emit()

func _tick_grow() -> void:
	var u := fmod(_t, DUR_GROW) / DUR_GROW
	_harvest.modulate.a = (0.25 + 0.2 * sin(u * TAU)) if harvest_glow else 0.0
	_dew.modulate.a = 0.15 + 0.15 * sin(u * TAU * 2.0)
	_crop_pulse.modulate.a = 0.2
	var s := 1.0 + 0.03 * sin(u * TAU)
	_crop_pulse.scale = Vector2(s, s)

func smoothstep(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / maxf(e1 - e0, 0.0001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
