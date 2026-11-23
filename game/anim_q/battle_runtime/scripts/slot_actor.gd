extends Node2D
## Presentation ONLY. BattleTimeline owns event timing, HP, statuses, skip and settlement.
## One persistent actor per side, independent body/action and incoming-hit channels.
const Fighter := preload("res://anim_q/battle_runtime/scripts/fighter_actor.gd")
@export_enum("player", "boss") var actor_side := "player"
var fighter: Node2D
var sword: AnimatedSprite2D
var blast: AnimatedSprite2D
var arena: Control
var fallback: Node2D
var playback_speed := 1.0
var capture_mode := false
var action := "idle"
var action_time := 0.0
var hit_time := -1.0
var skill_delay := 1.21
var shown_slot := "idle"
var _factor := 1.0
var _draft := {}
var _replace_body := false
var _draft_body: Sprite2D
var _draft_projectile: Sprite2D
var _draft_impact: Sprite2D
var _draft_error: Label

func _ready() -> void:
	# Fallback intro/reset can re-show its rigs. Suppress bodies after their update,
	# without disabling BossBattleFx (its intro, timing and anchor APIs remain live).
	process_priority = 100
	fighter = Fighter.new()
	fighter.name = "Fighter"
	add_child(fighter)
	fighter.setup(actor_side == "player", Vector2.ZERO, 280.0 if actor_side == "player" else 300.0)
	sword = _make_fx("技能特效-剑气", 7, 1.25)
	blast = _make_fx("技能特效-爆炸", 6, 0.85)
	blast.modulate.a = 0.72

func setup_presentation(host: Control, fx: Node2D) -> void:
	arena = host
	fallback = fx
	skill_delay = maxf(0.75, float(fx.call("skill_impact_delay")))
	if not arena.resized.is_connected(_layout): arena.resized.connect(_layout)
	_layout()
	_suppress_placeholders()

func _make_fx(label: String, count: int, factor: float) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.name = label
	sprite.sprite_frames = SpriteFrames.new()
	for i in count:
		sprite.sprite_frames.add_frame("default", load("res://anim_q/battle_runtime/frames/fx/" + label + "/%02d.png" % i))
	sprite.centered = false
	sprite.offset = Vector2(-160, -210)
	sprite.scale = Vector2.ONE * factor
	sprite.z_index = 6
	sprite.hide()
	add_child(sprite)
	return sprite

func _layout() -> void:
	if not is_instance_valid(arena) or arena.size.x <= 0 or arena.size.y <= 0: return
	# This is ONLY the middle flex arena, never a 1080x2340 full-screen canvas.
	_factor = minf(arena.size.x / 1080.0, minf(arena.size.y / 800.0, 1.0))
	scale = Vector2.ONE * _factor
	position = Vector2(arena.size.x * (0.25 if actor_side == "player" else 0.75), arena.size.y * 0.66)
	_update_anchor()

func body_rect() -> Rect2:
	var height := (280.0 if actor_side == "player" else 300.0) * _factor
	return Rect2(position - Vector2(height * 0.40, height), Vector2(height * 0.80, height))

func _update_anchor() -> void:
	if is_instance_valid(fallback):
		fallback.set("_hero_rect" if actor_side == "player" else "_boss_rect", body_rect())

func _suppress_placeholders() -> void:
	if not is_instance_valid(arena) or not is_instance_valid(fallback): return
	var names := ["HeroArt", "BattleHero"] if actor_side == "player" else ["BossArt"]
	for label in names:
		var placeholder := arena.get_node_or_null(NodePath(label)) as CanvasItem
		if placeholder != null: placeholder.hide()
	var rig := fallback.get("hero_rig" if actor_side == "player" else "boss") as CanvasItem
	if is_instance_valid(rig): rig.hide()
	_update_anchor()

func set_playback_speed(value: float) -> void:
	playback_speed = clampf(value, 0.1, 3.0)

func play_slot(slot: String, event: Dictionary = {}, speed: float = 1.0) -> void:
	set_playback_speed(speed)
	_suppress_placeholders()
	shown_slot = slot
	if slot == "hit":
		# Timeline may also call hit for a zero-damage/status event. Do not invent a reaction.
		if bool(event.get("dodged", false)) or float(event.get("damage", 1)) <= 0: return
		hit_time = 0.0
		fighter.command("hit")
		blast.position = Vector2(0, -5)
		blast.frame = 0
		blast.show()
		return
	if slot in ["skill", "ult"] and is_instance_valid(fallback):
		# Fallback's deferred HeroRig setup can change the official windup after _ready.
		skill_delay = maxf(0.75, float(fallback.call("skill_impact_delay")))
	action = "skill" if slot in ["skill", "ult"] else slot
	action_time = 0.0
	if slot == "idle":
		hit_time = -1.0
		fighter.reset_fighter()
		sword.hide()
		blast.hide()
	elif slot in ["win", "lose"]:
		hit_time = -1.0
		sword.hide()
		blast.hide()
		fighter.command("victory" if slot == "win" else "down")
	elif hit_time < 0.0:
		fighter.command("cast" if action == "skill" else "attack")

func _process(delta: float) -> void:
	_suppress_placeholders()
	if not capture_mode and is_visible_in_tree(): advance_presentation(delta)

func advance_presentation(delta: float) -> void:
	var left := maxf(delta * playback_speed, 0.0)
	while left > 0.000001:
		var step := minf(left, 1.0 / 120.0)
		_advance(step)
		left -= step

func _advance(delta: float) -> void:
	action_time += delta
	if hit_time >= 0.0:
		hit_time += delta
		var limit := _hit_limit()
		if _draft_list("impact").is_empty():
			blast.frame = mini(int(hit_time / 0.36 * 6), 5)
			if _draft_impact != null:
				_draft_impact.hide()
		else:
			blast.hide()
			_show_draft_sprite(_draft_impact, _frame_at("impact", hit_time, false), 180.0, Vector2(0, -80))
		if hit_time >= limit:
			hit_time = -1.0
			blast.hide()
			if _draft_impact != null:
				_draft_impact.hide()
	var wanted := "idle"
	match action:
		"attack":
			wanted = "attack" if action_time < 0.50 else "recover" if action_time < 0.74 else "idle"
		"skill":
			wanted = "cast" if action_time < skill_delay * 0.37 else "skill" if action_time < skill_delay + 0.16 else "recover" if action_time < skill_delay + 0.42 else "idle"
		"win": wanted = "victory"
		"lose": wanted = "down"
	if hit_time >= 0.0: wanted = "hit"
	if fighter.state != wanted: fighter.command(wanted)
	fighter.advance(delta)
	# Cast / release / accelerated flight align with the OFFICIAL impact delay.
	var flight_start := skill_delay * 0.66
	sword.visible = action == "skill" and actor_side == "player" and action_time >= flight_start and action_time < skill_delay
	if sword.visible:
		var progress := clampf((action_time - flight_start) / (skill_delay - flight_start), 0, 0.999)
		var travel := 0.35 * progress + 0.65 * progress * progress
		var gap := arena.size.x * 0.5 / maxf(_factor, 0.01) if is_instance_valid(arena) else 540.0
		sword.position = Vector2(65, -100).lerp(Vector2(gap - 15, -100), travel)
		sword.frame = mini(int(progress * 7), 6)
	_present_saved_body()
	_present_saved_projectile()
	_suppress_placeholders()


func apply_saved_playback(payload: Dictionary, replace_body: bool) -> void:
	_draft = payload
	_replace_body = replace_body
	_ensure_draft_nodes()


func _ensure_draft_nodes() -> void:
	if _draft_body == null:
		_draft_body = Sprite2D.new()
		_draft_body.name = "SavedBody"
		_draft_body.z_index = 5
		add_child(_draft_body)
		_draft_body.hide()
	if _draft_projectile == null:
		_draft_projectile = Sprite2D.new()
		_draft_projectile.name = "SavedProjectile"
		_draft_projectile.z_index = 6
		add_child(_draft_projectile)
		_draft_projectile.hide()
	if _draft_impact == null:
		_draft_impact = Sprite2D.new()
		_draft_impact.name = "SavedImpact"
		_draft_impact.z_index = 7
		add_child(_draft_impact)
		_draft_impact.hide()
	if _draft_error == null:
		_draft_error = Label.new()
		_draft_error.name = "SavedPlaybackError"
		_draft_error.text = "这一下的画面没载入"
		_draft_error.position = Vector2(-80, -160)
		_draft_error.z_index = 8
		add_child(_draft_error)
		_draft_error.hide()


func _draft_list(action_name: String) -> Array:
	var actions: Dictionary = _draft.get("actions", {})
	var value: Variant = actions.get(action_name, [])
	return value if value is Array else []


func _draft_failed(action_name: String) -> bool:
	var failed: Dictionary = _draft.get("failed", {})
	return bool(failed.get(action_name, false))


func _duration_sec(action_name: String) -> float:
	var total := 0.0
	for frame in _draft_list(action_name):
		total += float(frame.get("duration_ms", 83))
	return total / 1000.0


func _hit_limit() -> float:
	var limit := 0.36
	if _replace_body and not _draft_list("hit").is_empty():
		limit = maxf(0.05, _duration_sec("hit"))
	if not _draft_list("impact").is_empty():
		limit = maxf(limit, _duration_sec("impact"))
	return limit


func _frame_at(action_name: String, time_sec: float, loop_frames: bool) -> Dictionary:
	var frames := _draft_list(action_name)
	if frames.is_empty():
		return {}
	var elapsed := maxf(time_sec, 0.0) * 1000.0
	var total := 0.0
	for frame in frames:
		total += float(frame.get("duration_ms", 83))
	if total <= 0.0:
		return frames[0]
	if loop_frames:
		elapsed = fmod(elapsed, total)
	var cursor := 0.0
	for frame in frames:
		cursor += float(frame.get("duration_ms", 83))
		if elapsed < cursor:
			return frame
	return frames[frames.size() - 1]


func _show_draft_sprite(sprite: Sprite2D, frame: Dictionary, height: float, at: Vector2) -> void:
	var texture: Texture2D = frame.get("texture")
	if sprite == null or texture == null:
		if sprite != null:
			sprite.hide()
		return
	sprite.texture = texture
	sprite.centered = false
	sprite.position = at
	var tex_h := maxf(texture.get_height(), 1.0)
	sprite.scale = Vector2(height / tex_h, height / tex_h)
	sprite.offset = Vector2(-texture.get_width() / 2.0, -tex_h)
	sprite.show()


func _present_saved_body() -> void:
	if _draft_body == null:
		return
	var pose := ""
	if hit_time >= 0.0:
		pose = "hit"
	elif action == "attack":
		pose = "attack"
	elif action == "idle":
		pose = "idle"
	if pose != "" and _replace_body and _draft_failed(pose):
		fighter.visible = false
		_draft_body.hide()
		_draft_error.show()
		return
	if pose != "" and _replace_body and not _draft_list(pose).is_empty():
		fighter.visible = false
		if _draft_error != null:
			_draft_error.hide()
		var time := hit_time if pose == "hit" else action_time
		_show_draft_sprite(_draft_body, _frame_at(pose, time, pose == "idle"), 280.0, Vector2.ZERO)
		return
	fighter.visible = true
	_draft_body.hide()
	if _draft_error != null:
		_draft_error.hide()


func _present_saved_projectile() -> void:
	if _draft_projectile == null:
		return
	var frames := _draft_list("projectile")
	if actor_side != "player" or action != "attack" or frames.is_empty() or _draft_failed("projectile"):
		_draft_projectile.hide()
		return
	var start := _offset_before_frame("attack", int(_draft.get("projectileFrame", 1)))
	var duration := _duration_sec("projectile")
	if action_time < start or action_time >= start + duration:
		_draft_projectile.hide()
		return
	var progress := clampf((action_time - start) / maxf(duration, 0.001), 0.0, 1.0)
	var gap := arena.size.x * 0.5 / maxf(_factor, 0.01) if is_instance_valid(arena) else 540.0
	var at := Vector2(40, -140).lerp(Vector2(gap - 40, -140), progress)
	_show_draft_sprite(_draft_projectile, _frame_at("projectile", action_time - start, false), 140.0, at)


func _offset_before_frame(action_name: String, frame_number: int) -> float:
	var frames := _draft_list(action_name)
	var count := mini(maxi(frame_number - 1, 0), frames.size())
	var ms := 0.0
	for i in count:
		ms += float(frames[i].get("duration_ms", 83))
	return ms / 1000.0
