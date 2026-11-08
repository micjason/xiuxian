extends Node2D
## Foot anchored art; the director commands poses, code supplies breath/inertia.
const ROOT := "res://anim_q/battle_runtime/frames/hero/"
const ACTIONS := {"普通攻击":5, "技能攻击":4, "技能施放":5, "受击":4, "倒地":5, "胜利":3}
var sprite: AnimatedSprite2D
var is_hero := true
var state := "idle"
var state_time := 0.0
var life_time := 0.0
var velocity := Vector2.ZERO
var displacement := Vector2.ZERO
var pause_left := 0.0
var base_scale := 1.0
var facing := 1.0
var home := Vector2.ZERO

func setup(hero: bool, feet: Vector2, display_height: float) -> void:
	is_hero = hero
	facing = 1.0 if hero else -1.0
	home = feet
	position = home
	sprite = AnimatedSprite2D.new()
	sprite.name = "Body"
	sprite.centered = false
	sprite.sprite_frames = SpriteFrames.new()
	sprite.sprite_frames.remove_animation("default")
	if hero:
		base_scale = display_height / 130.0
		sprite.offset = Vector2(-240, -280)
		for action: String in ACTIONS:
			sprite.sprite_frames.add_animation(action)
			for i in int(ACTIONS[action]):
				sprite.sprite_frames.add_frame(action, load(ROOT + action + "/%02d.png" % i))
		sprite.sprite_frames.add_animation("idle")
		# One settled pose, NOT a slowed walk cycle.
		sprite.sprite_frames.add_frame("idle", load(ROOT + "技能施放/00.png"))
	else:
		var texture: Texture2D = load("res://assets/art/q/sprites/boss_bear.png")
		base_scale = display_height / 678.0
		sprite.offset = Vector2(-263, -693)
		for action in ["idle", "普通攻击", "技能攻击", "技能施放", "受击", "倒地", "胜利"]:
			sprite.sprite_frames.add_animation(action)
			sprite.sprite_frames.add_frame(action, texture)
	add_child(sprite)
	command("idle")
	advance(0.0)

func reset_fighter() -> void:
	velocity = Vector2.ZERO
	displacement = Vector2.ZERO
	pause_left = 0.0
	life_time = 0.0
	rotation = 0.0
	command("idle")
	advance(0.0)

func command(next: String) -> void:
	state = next
	state_time = 0.0
	sprite.modulate = Color.WHITE
	match state:
		"attack": velocity = Vector2(210.0 * facing, -18.0)
		"hit":
			velocity = Vector2(-190.0 * facing, -28.0)
			pause_left = 0.07 # impact hold, followed by recoil and spring return
		"recover", "idle": pause_left = 0.0
	var pose: String = {"idle":"idle", "cast":"技能施放", "attack":"普通攻击", "skill":"技能攻击", "hit":"受击", "down":"倒地", "victory":"胜利"}.get(state, "idle")
	sprite.animation = pose
	sprite.frame = 0
	if state == "skill": velocity = Vector2(180.0 * facing, -12.0)

func advance(delta: float) -> void:
	life_time += delta
	state_time += delta
	# Fixed bounded steps keep spring integration stable even during fast playback.
	if pause_left > 0.0:
		pause_left = maxf(0.0, pause_left - delta)
	else:
		var acceleration := -displacement * 85.0 - velocity * 15.0
		velocity += acceleration * delta
		displacement += velocity * delta
		displacement.x = clampf(displacement.x, -42.0, 42.0)
		displacement.y = clampf(displacement.y, -10.0, 8.0)
	var breath := sin(life_time * TAU / 2.6 + (0.0 if is_hero else 1.3))
	var resting := state in ["idle", "recover", "cast"]
	sprite.scale = Vector2(base_scale * (1.0 - breath * 0.003 if resting else 1.0), base_scale * (1.0 + breath * 0.012 if resting else 1.0))
	position = home + displacement
	sprite.position.y = -breath * 1.2 if resting else 0.0
	var count := sprite.sprite_frames.get_frame_count(sprite.animation)
	# The director ends actions. Never let a non-loop clip restart itself.
	sprite.frame = mini(int(state_time * 10.0), count - 1)
	# Sheet down frames finish with a get-up; retain the grounded third pose.
	if state == "down" and is_hero: sprite.frame = mini(int(state_time * 10.0), 2)
	if state == "hit": sprite.modulate = Color(1.0, 0.68, 0.57) if state_time < 0.18 else Color.WHITE
	rotation = -facing * 0.028 * sin(minf(state_time / 0.5, 1.0) * PI) if state == "hit" else 0.0
	if state == "down" and not is_hero:
		rotation = -0.65 * minf(state_time / 0.5, 1.0)
		sprite.modulate = Color(0.65, 0.65, 0.72, 0.85)
