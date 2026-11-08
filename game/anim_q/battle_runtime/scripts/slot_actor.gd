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
		blast.frame = mini(int(hit_time / 0.36 * 6), 5)
		if hit_time >= 0.36:
			hit_time = -1.0
			blast.hide()
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
	_suppress_placeholders()
