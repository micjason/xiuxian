extends Node2D
## Presentation-only actors for the shared TimelineBattlePage. Feet are fixed,
## hero changes actual sheet poses; enemy has independent local joint motion.
const EnemyPose := preload("res://anim_q/battle_runtime/scripts/enemy_pose.gd")
const ROOT := "res://anim_q/battle_runtime/frames/hero/"
const HERO_ANCHOR := Vector2(240, 280)
const ACTIONS := {"attack": ["普通攻击", 5], "skill": ["技能攻击", 4], "hit": ["受击", 4], "win": ["胜利", 3], "lose": ["倒地", 5]}
var player := AnimatedSprite2D.new()
var enemy := EnemyPose.new()
var display_height := 280.0
var arena: Control
var fx: Node2D
var _hero_art: CanvasItem
var _boss_art: TextureRect
var _elapsed := 0.0
var _player_slot := "idle"
var _last_size := Vector2.ZERO
var _speed := 1.0

func setup(host: Control, legacy_fx: Node2D) -> void:
	name = "CombatCast"
	arena = host
	fx = legacy_fx
	_hero_art = fx.get("hero")
	_boss_art = fx.get("boss_art") as TextureRect
	# Run after legacy FX, so resets/appearance cannot reveal old static rigs.
	process_priority = 100
	player.name = "PlayerFrames"
	player.centered = false
	player.offset = -HERO_ANCHOR
	player.sprite_frames = _frames()
	add_child(player)
	enemy.name = "EnemyJoints"
	add_child(enemy)
	host.add_child(self)
	host.resized.connect(_layout)
	reset_cast()

func _frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.set_animation_speed("idle", 2.42)
	for i in [2, 3, 4, 3]:
		frames.add_frame("idle", load(ROOT + "移动/%02d.png" % i))
	for slot: String in ACTIONS:
		frames.add_animation(slot)
		frames.set_animation_loop(slot, false)
		frames.set_animation_speed(slot, 11.0)
		if slot == "skill":
			for i in 5:
				frames.add_frame(slot, load(ROOT + "技能施放/%02d.png" % i))
		for i in int(ACTIONS[slot][1]):
			frames.add_frame(slot, load(ROOT + str(ACTIONS[slot][0]) + "/%02d.png" % i))
	return frames

func reset_cast() -> void:
	_player_slot = "idle"
	_elapsed = 0
	enemy.play_slot("idle")
	_layout()
	_sync_art()
	_hide_legacy()
	advance_pose(0)

func _layout() -> void:
	if arena == null or arena.size.x <= 0 or arena.size.y <= 0:
		return
	_last_size = arena.size
	var k := minf(1.0, minf(arena.size.x / 1032.0, arena.size.y / 1182.0))
	display_height = 280.0 * k
	# At 1080x2340: global feet ~ (260,1280), (820,1280).
	var feet := arena.size.y * 0.577
	player.position = Vector2(arena.size.x * 0.23, feet)
	enemy.position = Vector2(arena.size.x * 0.77, feet)
	player.scale = Vector2.ONE * display_height / 130.0
	var hero_rect := Rect2(player.position - Vector2(display_height * 0.5, display_height), Vector2.ONE * display_height)
	var enemy_rect := Rect2(enemy.position - Vector2(display_height * 0.54, display_height * 1.07), Vector2(display_height * 1.08, display_height * 1.07))
	# Invisible legacy rects remain the sole FX/status/HP anchoring contract.
	for pair: Array in [[_hero_art, hero_rect], [_boss_art, enemy_rect]]:
		if pair[0] is Control:
			var c := pair[0] as Control
			c.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			c.position = (pair[1] as Rect2).position
			c.size = (pair[1] as Rect2).size
	fx.call("_layout")
	_sync_art()

func _sync_art() -> void:
	if _boss_art == null or _boss_art.texture == null:
		return
	var tex := _boss_art.texture
	var flip := _boss_art.flip_h
	# Supplied mon_* originals face left; the old ArtLib flip table described
	# earlier art. Keep that global contract untouched for all other pages.
	var raw_path := tex.resource_path.replace("/boss_", "/mon_")
	if ResourceLoader.exists(raw_path) and raw_path.contains("/q/sprites/mon_"):
		tex = load(raw_path)
		flip = false
	enemy.set_art(tex, flip, display_height * 1.07)

func _hide_legacy() -> void:
	if _hero_art != null:
		_hero_art.hide()
	if _boss_art != null:
		_boss_art.hide()
	for rig: Variant in [fx.get("hero_rig"), fx.get("boss")]:
		if rig is CanvasItem:
			rig.hide()

func play_slot(side: String, slot: String, _event: Dictionary, speed: float) -> void:
	_speed = speed
	if side == "boss":
		enemy.play_slot(slot)
		return
	if side != "player":
		return
	if slot == "hit" and _player_slot in ["attack", "skill"]:
		return
	_player_slot = "skill" if slot == "ult" else slot
	_elapsed = 0
	advance_pose(0)

func advance_pose(delta: float) -> void:
	_elapsed += delta
	var frames := player.sprite_frames
	var fps := frames.get_animation_speed(_player_slot)
	var count := frames.get_frame_count(_player_slot)
	var index := int(_elapsed * fps)
	if index >= count and _player_slot not in ["idle", "win", "lose"]:
		_player_slot = "idle"
		_elapsed = 0
		index = 0
		count = frames.get_frame_count("idle")
	player.animation = _player_slot
	player.frame = index % count if _player_slot == "idle" else mini(index, count - 1)
	enemy.advance_pose(delta)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if arena.size != _last_size:
		_layout()
	_speed = float(fx.get("playback_speed"))
	_sync_art()
	_hide_legacy()
	advance_pose(delta * _speed)
