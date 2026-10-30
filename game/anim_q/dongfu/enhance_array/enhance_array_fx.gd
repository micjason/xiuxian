extends Node2D
## 洞府·强化法阵走光（静暖）
## 成功：细金线沿卦位/符文环走通 → 向心灵石 → ≤0.4s 金闪星屑（不加大爆）
signal finished
signal enhance_success
signal enhance_fail

const DUR_RING := 0.90
const DUR_INWARD := 0.16
const DUR_FLASH := 0.36
const DUR_FAIL := 0.85
const DUR_IDLE := 3.00
const NODE_COUNT := 8
const TRAIL_POINTS := 48

@export var fx_scale := 1.0
@export var autoplay_idle := true
@export var radius := 150.0
@export var inner_radius := 92.0

var _mode := "idle"  # idle | success | fail | ""
var _t := 0.0

@onready var _root: Node2D = $Root
@onready var _ring: Sprite2D = $Root/IdleRing
@onready var _trail: Line2D = $Root/Trail
@onready var _trail_inner: Line2D = $Root/TrailInner
@onready var _spoke: Line2D = $Root/Spoke
@onready var _bead: Sprite2D = $Root/Bead
@onready var _flash: Sprite2D = $Root/SuccessFlash
@onready var _nodes: Node2D = $Root/Nodes
@onready var _sparks: CPUParticles2D = $Root/Sparks

func _ready() -> void:
	_root.scale = Vector2(fx_scale, fx_scale)
	_layout_nodes()
	_setup_lines()
	_reset_vis()
	if autoplay_idle:
		play_idle()
	else:
		set_process(false)

func _setup_lines() -> void:
	_trail.clear_points()
	_trail.width = 3.0
	_trail.default_color = Color(1.0, 0.85, 0.54, 0.95)  # #FFD98A
	_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	_trail_inner.clear_points()
	_trail_inner.width = 2.2
	_trail_inner.default_color = Color(1.0, 0.62, 0.26, 0.85)  # #FF9F43-ish
	_trail_inner.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail_inner.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail_inner.end_cap_mode = Line2D.LINE_CAP_ROUND
	_spoke.clear_points()
	_spoke.width = 2.4
	_spoke.default_color = Color(1.0, 0.78, 0.45, 0.9)
	_spoke.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_spoke.end_cap_mode = Line2D.LINE_CAP_ROUND

func _layout_nodes() -> void:
	for i in range(NODE_COUNT):
		var n: Sprite2D = _nodes.get_child(i) as Sprite2D
		var a := -PI * 0.5 + i * TAU / NODE_COUNT
		n.position = Vector2(cos(a), sin(a)) * radius

func _reset_vis() -> void:
	_bead.modulate.a = 0.0
	_flash.modulate.a = 0.0
	_sparks.emitting = false
	_trail.clear_points()
	_trail_inner.clear_points()
	_spoke.clear_points()
	_trail.modulate.a = 1.0
	_trail_inner.modulate.a = 1.0
	_spoke.modulate.a = 1.0
	for c in _nodes.get_children():
		(c as Sprite2D).modulate.a = 0.15

func play_idle(at: Vector2 = Vector2.INF) -> void:
	if at != Vector2.INF:
		position = at
	_mode = "idle"
	_t = 0.0
	_reset_vis()
	set_process(true)

func play_enhance_success(at: Vector2 = Vector2.INF) -> void:
	if not is_node_ready():
		call_deferred("play_enhance_success", at)
		return
	if at != Vector2.INF:
		position = at
	_mode = "success"
	_t = 0.0
	_reset_vis()
	set_process(true)

func play_enhance_fail(at: Vector2 = Vector2.INF) -> void:
	if not is_node_ready():
		call_deferred("play_enhance_fail", at)
		return
	if at != Vector2.INF:
		position = at
	_mode = "fail"
	_t = 0.0
	_reset_vis()
	set_process(true)

func stop() -> void:
	_mode = ""
	_reset_vis()
	set_process(false)

func is_playing() -> bool:
	return _mode == "success" or _mode == "fail"

func _process(dt: float) -> void:
	_t += dt
	match _mode:
		"idle":
			_tick_idle()
		"success":
			_tick_success()
		"fail":
			_tick_fail()

func _tick_idle() -> void:
	var u := fmod(_t, DUR_IDLE) / DUR_IDLE
	_ring.modulate.a = 0.18 + 0.1 * sin(u * TAU)
	_ring.rotation = u * TAU * 0.12
	for i in range(NODE_COUNT):
		var n: Sprite2D = _nodes.get_child(i) as Sprite2D
		n.modulate.a = 0.1 + 0.08 * sin(u * TAU + i * 0.7)

func _fill_arc(line: Line2D, rad: float, progress: float, pts: int = TRAIL_POINTS) -> void:
	line.clear_points()
	var n := maxi(2, int(ceil(progress * pts)))
	for i in range(n + 1):
		var u := float(i) / float(pts)
		if u > progress:
			break
		var ang := -PI * 0.5 + u * TAU
		line.add_point(Vector2(cos(ang), sin(ang)) * rad)

func _tick_success() -> void:
	var t_ring := DUR_RING
	var t_in := DUR_RING + DUR_INWARD
	var t_end := t_in + DUR_FLASH
	if _t <= t_ring:
		# Phase A: thin gold line walks bagua + rune rings
		var u := _t / t_ring
		_ring.modulate.a = 0.12 + 0.28 * u
		_fill_arc(_trail, radius, u)
		_fill_arc(_trail_inner, inner_radius, maxf(0.0, u - 0.04))
		# gradient-ish: brighten trail head via bead
		_bead.modulate.a = 0.98
		var ang := -PI * 0.5 + u * TAU
		_bead.position = Vector2(cos(ang), sin(ang)) * radius
		var lit := int(floor(u * NODE_COUNT + 0.001))
		for i in range(NODE_COUNT):
			var n: Sprite2D = _nodes.get_child(i) as Sprite2D
			n.modulate.a = 0.9 if i <= lit else 0.1
		_spoke.clear_points()
	elif _t <= t_in:
		# Phase B: line runs ring → center spirit stone
		var u := clampf((_t - t_ring) / DUR_INWARD, 0.0, 1.0)
		_fill_arc(_trail, radius, 1.0)
		_fill_arc(_trail_inner, inner_radius, 1.0)
		for i in range(NODE_COUNT):
			(_nodes.get_child(i) as Sprite2D).modulate.a = 0.85
		_ring.modulate.a = 0.4
		# spoke from top of ring (where arc closed) inward — actually from last bead (full circle top) to center
		var start := Vector2(0, -radius)
		var end := Vector2.ZERO.lerp(start, 1.0 - u)  # move bead toward center
		_spoke.clear_points()
		_spoke.add_point(start)
		_spoke.add_point(end)
		_bead.modulate.a = 0.98
		_bead.position = end
	else:
		# Phase C: brief center flash + star dust (keep current intensity)
		var u := clampf((_t - t_in) / DUR_FLASH, 0.0, 1.0)
		_fill_arc(_trail, radius, 1.0)
		_fill_arc(_trail_inner, inner_radius, 1.0)
		_spoke.clear_points()
		_spoke.add_point(Vector2(0, -radius))
		_spoke.add_point(Vector2.ZERO)
		_bead.modulate.a = 0.0
		_flash.modulate.a = sin(u * PI) * 0.9
		_flash.scale = Vector2.ONE * (0.8 + 0.35 * u)  # do NOT enlarge boom
		for c in _nodes.get_children():
			(c as Sprite2D).modulate.a = 1.0
		# fade trails slightly so flash reads without thick wash
		_trail.modulate.a = 0.75
		_trail_inner.modulate.a = 0.7
		_spoke.modulate.a = 0.65
		if u > 0.12 and not _sparks.emitting:
			_sparks.restart()
			_sparks.emitting = true
		if u >= 1.0:
			_sparks.emitting = false
			_mode = "idle"
			_t = 0.0
			enhance_success.emit()
			finished.emit()

func _tick_fail() -> void:
	var u := clampf(_t / DUR_FAIL, 0.0, 1.0)
	var progress := u * 0.62
	_fill_arc(_trail, radius, progress)
	_fill_arc(_trail_inner, inner_radius, maxf(0.0, progress - 0.04))
	_bead.modulate.a = 0.9 * (1.0 - smoothstep(0.55, 0.75, u))
	var ang := -PI * 0.5 + progress * TAU
	_bead.position = Vector2(cos(ang), sin(ang)) * radius
	var lit := int(floor(progress * NODE_COUNT))
	for i in range(NODE_COUNT):
		var n: Sprite2D = _nodes.get_child(i) as Sprite2D
		if i < lit:
			n.modulate.a = 0.7 * (1.0 - smoothstep(0.6, 1.0, u))
		else:
			n.modulate.a = 0.1
	if u >= 0.7:
		# extinguish at gap
		_trail.modulate.a = 1.0 - smoothstep(0.7, 1.0, u)
		_trail_inner.modulate.a = _trail.modulate.a
	if u >= 1.0:
		_mode = "idle"
		_t = 0.0
		enhance_fail.emit()
		finished.emit()

func smoothstep(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / maxf(e1 - e0, 0.0001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
