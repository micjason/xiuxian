extends Node2D
## Locally articulated UV mesh. Head, striking limb and tail/wing have independent
## pivots; rear feet and root stay planted. No rigid-card lunge, scale or wobble.
const GRID := 20
var mesh := Polygon2D.new()
var slot := "idle"
var elapsed := 0.0
var idle_clock := 0.0
var display_height := 300.0
var _texture: Texture2D
var _rest := PackedVector2Array()
var _uv := PackedVector2Array()
var _profile := "quadruped"
var _flip := false
var _size := Vector2.ONE
var _used := Rect2(Vector2.ZERO, Vector2.ONE)

func _init() -> void:
	mesh.name = "JointMesh"
	add_child(mesh)

func set_art(tex: Texture2D, flip: bool, height: float) -> void:
	if tex == null:
		return
	if tex == _texture and is_equal_approx(height, display_height) and flip == _flip:
		return
	_texture = tex
	_flip = flip
	display_height = height
	_size = tex.get_size()
	var image := tex.get_image()
	if image.is_compressed():
		image.decompress()
	_used = Rect2(image.get_used_rect())
	var file := tex.resource_path.get_file()
	_profile = "quadruped"
	if file.contains("bear") or file.contains("golem") or file.contains("elder"):
		_profile = "biped"
	elif file.contains("bat") or file.contains("crow"):
		_profile = "winged"
	elif file.contains("snake") or file.contains("jiao") or file.contains("ghost"):
		_profile = "serpent"
	mesh.texture = tex
	_rest.clear()
	_uv.clear()
	var triangles: Array[PackedInt32Array] = []
	for y in GRID + 1:
		for x in GRID + 1:
			var p := Vector2(float(x) / GRID, float(y) / GRID)
			_rest.append(p)
			_uv.append(p * _size)
	for y in GRID:
		for x in GRID:
			var i := y * (GRID + 1) + x
			triangles.append(PackedInt32Array([i, i + 1, i + GRID + 1]))
			triangles.append(PackedInt32Array([i + 1, i + GRID + 2, i + GRID + 1]))
	mesh.uv = _uv
	mesh.polygons = triangles
	advance_pose(0)

func play_slot(value: String) -> void:
	# A hit adds a reaction without erasing an outgoing strike halfway through.
	if value == "hit" and slot in ["attack", "skill", "ult"] and elapsed < 0.4:
		return
	slot = value
	elapsed = 0.0

func advance_pose(delta: float) -> void:
	elapsed += delta
	idle_clock += delta
	if slot not in ["idle", "lose", "win"] and elapsed > (0.8 if slot in ["skill", "ult"] else 0.55):
		slot = "idle"
		elapsed = 0.0
	if _rest.is_empty():
		return
	var strike := 0.0
	if slot in ["attack", "skill", "ult"]:
		var duration := 0.8 if slot in ["skill", "ult"] else 0.55
		strike = sin(PI * clampf(elapsed / duration, 0, 1))
	var head_angle := sin(idle_clock * 2.1) * 0.045 - strike * 0.2
	var limb_angle := sin(idle_clock * 2.1 + 1.1) * 0.09 + strike * 1.15
	var tail_angle := sin(idle_clock * 2.5) * 0.18 - strike * 0.3
	if slot == "hit":
		head_angle += sin(PI * minf(1, elapsed / 0.4)) * 0.28
	if slot == "lose":
		head_angle = 0.28 * minf(elapsed / 0.5, 1)
		limb_angle = -0.3 * minf(elapsed / 0.5, 1)
	var points := PackedVector2Array()
	points.resize(_rest.size())
	var k := display_height / maxf(1, _used.size.y)
	for i in _rest.size():
		# Joint profiles are in the visible art's coordinates (not its transparent pad).
		var p := (_rest[i] * _size - _used.position) / _used.size
		var q := _joint_pose(p, head_angle, limb_angle, tail_angle, strike)
		var pixel := _used.position + q * _used.size
		var local := (pixel - Vector2(_used.get_center().x, _used.end.y)) * k
		if _flip:
			local.x = -local.x
		points[i] = local
	mesh.polygon = points
	mesh.modulate = Color(0.65, 0.68, 0.72) if slot == "lose" else Color.WHITE

func _joint_pose(p: Vector2, head: float, limb: float, tail: float, strike: float) -> Vector2:
	var head_pivot := Vector2(0.43, 0.57)
	var arm_pivot := Vector2(0.42, 0.64)
	var head_weight := 1.0 - smoothstep(0.43, 0.65, p.y)
	var arm_weight := smoothstep(0.62, 0.81, p.y) * (1.0 - smoothstep(0.52, 0.70, p.x))
	var tail_weight := smoothstep(0.65, 0.84, p.x) * (1.0 - smoothstep(0.70, 0.90, p.y))
	if _profile == "biped":
		head_pivot = Vector2(0.48, 0.48)
		head_weight = 1.0 - smoothstep(0.40, 0.56, p.y)
		arm_pivot = Vector2(0.23, 0.55)
		arm_weight = (1.0 - smoothstep(0.22, 0.40, p.x)) * smoothstep(0.48, 0.65, p.y) * (1.0 - smoothstep(0.80, 0.93, p.y))
		tail_weight = 0.0
	elif _profile == "winged":
		arm_pivot = Vector2(0.30, 0.51)
		arm_weight = (1.0 - smoothstep(0.22, 0.42, p.x)) * smoothstep(0.36, 0.57, p.y) * (1.0 - smoothstep(0.78, 0.94, p.y))
		tail_weight *= 1.4
	elif _profile == "serpent":
		head_pivot = Vector2(0.45, 0.61)
		head_weight = 1.0 - smoothstep(0.38, 0.76, p.y)
		arm_weight = 0.0
		head -= strike * 0.35
	# Linear skinning around separate anatomical pivots, not a whole-image transform.
	return p + ((p - head_pivot).rotated(head) - (p - head_pivot)) * head_weight \
		+ ((p - arm_pivot).rotated(limb) - (p - arm_pivot)) * arm_weight \
		+ ((p - Vector2(0.72, 0.68)).rotated(tail) - (p - Vector2(0.72, 0.68))) * tail_weight
