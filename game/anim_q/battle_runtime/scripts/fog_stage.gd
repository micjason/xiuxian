extends Node2D
## Standalone full-canvas reference helper only; live arenas use combat_slots/actor.tscn.
const C := preload("res://anim_q/battle_runtime/scripts/battle_config.gd")
const Fighter := preload("res://anim_q/battle_runtime/scripts/fighter_actor.gd")
var hero: Node2D
var monster: Node2D
var sword: AnimatedSprite2D
var blast: AnimatedSprite2D

func _ready() -> void:
	var bg := TextureRect.new()
	bg.name = "PaintedBackground"
	bg.texture = load(C.TEX_BG)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.size = Vector2(1080, 1540)
	bg.modulate = Color(0.76, 0.83, 0.94)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	for x in [C.HERO_CENTER_X, C.BOSS_CENTER_X]:
		var shadow := Sprite2D.new()
		shadow.texture = load("res://anim_q/dongfu/alchemy_fire/fx/fx_contact_shadow.png")
		shadow.position = Vector2(x, C.FEET_Y + 5)
		shadow.scale = Vector2(0.65, 0.22)
		shadow.modulate.a = 0.55
		add_child(shadow)
	hero = Fighter.new()
	hero.name = "Hero"
	add_child(hero)
	hero.setup(true, Vector2(C.HERO_CENTER_X, C.FEET_Y), C.HERO_DISPLAY_H)
	monster = Fighter.new()
	monster.name = "Monster"
	add_child(monster)
	monster.setup(false, Vector2(C.BOSS_CENTER_X, C.FEET_Y), C.BOSS_DISPLAY_H)
	sword = _fx("技能特效-剑气", 7, 1.55)
	# Smaller, translucent impact sits at the feet; face/body stay readable.
	blast = _fx("技能特效-爆炸", 6, 1.0)
	blast.modulate.a = 0.72

func _fx(action: String, count: int, factor: float) -> AnimatedSprite2D:
	var fx := AnimatedSprite2D.new()
	fx.sprite_frames = SpriteFrames.new()
	for i in count:
		fx.sprite_frames.add_frame("default", load("res://anim_q/battle_runtime/frames/fx/" + action + "/%02d.png" % i))
	fx.centered = false
	fx.offset = Vector2(-160, -210)
	fx.scale = Vector2.ONE * factor
	fx.visible = false
	add_child(fx)
	return fx

func advance(delta: float) -> void:
	hero.advance(delta)
	monster.advance(delta)

func clear_effects() -> void:
	sword.hide()
	blast.hide()

func travel(player: bool, phase: float) -> void:
	sword.show()
	sword.flip_h = not player
	sword.modulate = Color.WHITE if player else Color(1.0, 0.63, 0.4)
	var from := Vector2(340, 1180) if player else Vector2(750, 1180)
	var to := Vector2(800, 1180) if player else Vector2(280, 1180)
	# Accelerating projectile: v0 + a*t, unlike constant-speed frame sliding.
	var eased := 0.35 * phase + 0.65 * phase * phase
	sword.position = from.lerp(to, eased)
	sword.frame = mini(int(phase * 7), 6)

func impact(player: bool, phase: float) -> void:
	sword.hide()
	blast.show()
	blast.position = Vector2(C.BOSS_CENTER_X if player else C.HERO_CENTER_X, C.FEET_Y - 5)
	blast.frame = mini(int(phase * 6), 5)
