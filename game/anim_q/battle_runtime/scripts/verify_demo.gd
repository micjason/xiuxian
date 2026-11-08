extends SceneTree
## Headless regression checks for the isolated timeline and shared foot anchor.
func _initialize() -> void:
	var scene: Node = load("res://anim_q/battle_runtime/scenes/battle_demo.tscn").instantiate()
	root.add_child(scene)
	scene.capture_mode = true
	await process_frame
	var hero: AnimatedSprite2D = scene.get_node("Characters/Hero")
	var boss: Sprite2D = scene.get_node("Characters/Boss")
	assert(boss.texture != null)
	var boss_position := boss.position
	var cases := {0.0:"idle", 2.2:"普通攻击", 3.5:"技能施放", 4.5:"技能攻击", 5.6:"idle", 8.6:"受击", 10.0:"idle", 14.0:"idle"}
	for t: float in cases:
		scene.seek_demo(t)
		assert(hero.animation == cases[t], "wrong phase at " + str(t))
		assert(hero.position == Vector2(260, 1280), "hero foot anchor moved")
		assert(boss.position == boss_position, "boss must remain still")
		assert(hero.offset == Vector2(-240, -280))
	for action: String in scene.ACTION_COUNTS:
		assert(hero.sprite_frames.get_frame_count(action) == scene.ACTION_COUNTS[action])
		assert(hero.sprite_frames.get_animation_speed(action) == 11.0)
	scene.seek_demo(4.6)
	assert(scene._sword.visible)
	scene.seek_demo(5.6)
	assert(scene._blast.visible)
	scene.seek_demo(7.8)
	assert(scene._counter.visible)
	scene.seek_demo(12.0)
	assert(not scene._sword.visible and not scene._blast.visible and not scene._counter.visible)
	assert(scene._log_text.text.contains("回到待战"))
	assert(scene.find_children("*", "Button", true, false).is_empty())
	print("BATTLE_RUNTIME_TESTS PASS: phase/actions/anchors/still-boss/fx/idle/no-buttons")
	quit()
