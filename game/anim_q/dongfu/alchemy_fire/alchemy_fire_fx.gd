extends Node2D
## 洞府·炼丹炉火青烟（静暖循环）
## 火周期 ~1.5s；alchemy_start on / alchemy_claim off+闪
signal finished
signal claim_done

const FIRE_PERIOD := 1.50
const CLAIM_DUR := 0.32

@export var fx_scale := 1.0
@export var intensity := 1.0  # 0..1.2
@export var autoplay := false

var _on := false
var _claiming := false
var _t := 0.0
var _ct := 0.0

@onready var _root: Node2D = $Root
@onready var _glow: Sprite2D = $Root/FireGlow
@onready var _outer: Sprite2D = $Root/FlameOuter
@onready var _core: Sprite2D = $Root/FlameCore
@onready var _smoke_a: Sprite2D = $Root/SmokeA
@onready var _smoke_b: Sprite2D = $Root/SmokeB
@onready var _smoke_c: Sprite2D = $Root/SmokeC
@onready var _embers: CPUParticles2D = $Root/Embers
@onready var _flash: Sprite2D = $Root/ClaimFlash

func _ready() -> void:
	_root.scale = Vector2(fx_scale, fx_scale)
	_flash.modulate.a = 0.0
	_set_idle_off()
	if autoplay:
		set_alchemy_on(true)

func set_alchemy_on(v: bool) -> void:
	_on = v
	_claiming = false
	if v:
		_t = 0.0
		_embers.emitting = true
		set_process(true)
	else:
		_embers.emitting = false
		_set_idle_off()
		set_process(false)

func set_alchemy_intensity(v: float) -> void:
	intensity = clampf(v, 0.0, 1.25)

func play_claim() -> void:
	_claiming = true
	_ct = 0.0
	_on = false
	_embers.emitting = false
	set_process(true)

func stop() -> void:
	set_alchemy_on(false)

func is_playing() -> bool:
	return _on or _claiming

func _set_idle_off() -> void:
	for s in [_glow, _outer, _core, _smoke_a, _smoke_b, _smoke_c]:
		s.modulate.a = 0.0

func _process(dt: float) -> void:
	if _claiming:
		_ct += dt
		var u := clampf(_ct / CLAIM_DUR, 0.0, 1.0)
		_flash.modulate.a = sin(u * PI) * 0.95
		_flash.scale = Vector2.ONE * (0.7 + 0.5 * u)
		_outer.modulate.a = (1.0 - u) * 0.4
		_core.modulate.a = (1.0 - u) * 0.5
		for s in [_smoke_a, _smoke_b, _smoke_c]:
			s.modulate.a = (1.0 - u) * 0.35
		if u >= 1.0:
			_claiming = false
			_flash.modulate.a = 0.0
			_set_idle_off()
			set_process(false)
			claim_done.emit()
			finished.emit()
		return
	if not _on:
		return
	_t += dt
	var phase := fmod(_t, FIRE_PERIOD) / FIRE_PERIOD
	# soft pulse 强弱
	var pulse := 0.55 + 0.45 * (0.5 + 0.5 * sin(phase * TAU))
	pulse *= intensity
	_glow.modulate.a = 0.35 * pulse
	_glow.scale = Vector2.ONE * (0.9 + 0.25 * pulse)
	_outer.modulate.a = 0.55 * pulse
	_outer.scale = Vector2(0.95 + 0.12 * pulse, 0.9 + 0.2 * pulse)
	_core.modulate.a = 0.75 * pulse
	_core.scale = Vector2(0.9 + 0.15 * pulse, 0.85 + 0.25 * pulse)
	# smoke rise + sway
	_tick_smoke(_smoke_a, _t * 0.35, 0.0, 0.45)
	_tick_smoke(_smoke_b, _t * 0.28 + 1.2, 8.0, 0.38)
	_tick_smoke(_smoke_c, _t * 0.22 + 2.4, -6.0, 0.32)

func _tick_smoke(s: Sprite2D, t: float, xoff: float, base_a: float) -> void:
	var u := fmod(t, 1.0)
	s.position = Vector2(xoff + sin(t * 1.7) * 6.0, -20.0 - u * 70.0)
	s.modulate.a = base_a * (1.0 - u) * intensity
	s.scale = Vector2.ONE * (0.7 + u * 0.55)
	s.rotation = sin(t * 1.1) * 0.12
