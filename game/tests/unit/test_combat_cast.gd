extends GutTest

func _page() -> TimelineBattlePage:
	var page := TimelineBattlePage.new()
	page.size = Vector2(1032, 2276)
	add_child_autofree(page)
	return page

func test_ready_cast_is_centered_small_and_uses_real_idle_frames() -> void:
	var page := _page()
	await get_tree().process_frame
	page.open_stage({}, {}, {"slug": "test", "bosses": [{"name": "青鬃狼王", "artKey": "wolf"}]}, {}, "")
	await get_tree().process_frame
	var cast: Node2D = page.get("_arena").get_node_or_null("CombatCast")
	assert_not_null(cast, "standalone cast replaces giant boss + bottom-left hero")
	if cast == null:
		return
	var arena: Control = page.get("_arena")
	var hero: AnimatedSprite2D = cast.get("player")
	var enemy: Node2D = cast.get("enemy")
	assert_almost_eq((hero.position.x + enemy.position.x) / 2.0, arena.size.x / 2.0, 0.1)
	assert_almost_eq(hero.position.y, enemy.position.y, 0.1)
	assert_lt(hero.position.y, arena.size.y * 0.7, "not bottom-left")
	assert_lte(cast.get("display_height"), 300.0)
	assert_eq(hero.sprite_frames.get_frame_count("idle"), 4)
	assert_ne(hero.sprite_frames.get_frame_texture("idle", 0), hero.sprite_frames.get_frame_texture("idle", 1))
	var stable_scale := hero.scale
	var stable_feet := hero.position
	var before_frame := hero.frame
	var before_mesh: PackedVector2Array = enemy.get("mesh").polygon
	cast.call("advance_pose", 0.5)
	assert_ne(hero.frame, before_frame, "ready actually advances pose frames")
	assert_ne(enemy.get("mesh").polygon, before_mesh, "ready enemy articulates its head/limb/tail")
	assert_eq(hero.scale, stable_scale, "idle has no breathing scale")
	assert_eq(hero.position, stable_feet, "feet do not slide")
	assert_false((page.get("_fx").get("boss") as CanvasItem).visible)
	page.abort()

func test_outgoing_attack_has_pose_frames_and_enemy_uses_joint_motion() -> void:
	var page := _page()
	await get_tree().process_frame
	page.open_stage({}, {}, {"slug": "test", "bosses": [{"name": "青鬃狼王", "artKey": "wolf"}]}, {}, "")
	var cast: Node2D = page.get("_arena").get_node_or_null("CombatCast")
	assert_not_null(cast)
	if cast == null:
		return
	var slots: RefCounted = page.get("_slots")
	slots.call("play_slot", "player", "attack", {"side": "player", "kind": "attack"})
	cast.call("advance_pose", 0.21)
	var hero: AnimatedSprite2D = cast.get("player")
	assert_eq(hero.animation, &"attack")
	assert_gte(hero.frame, 2)
	assert_eq(hero.sprite_frames.get_frame_count("attack"), 5)
	var enemy: Node2D = cast.get("enemy")
	var mesh: Polygon2D = enemy.get("mesh")
	var idle_points := mesh.polygon
	var feet := enemy.position
	slots.call("play_slot", "boss", "attack", {"side": "boss", "kind": "attack"})
	cast.call("advance_pose", 0.21)
	assert_ne(mesh.polygon, idle_points, "joint pose changes, not a rigid card")
	assert_eq(enemy.position, feet, "no whole-image lunge")
	assert_eq(enemy.scale, Vector2.ONE)
	assert_eq(enemy.rotation, 0.0)
	# At least the planted rear foot remains fixed while the striking limb moves.
	assert_eq(mesh.polygon[mesh.polygon.size() - 1], idle_points[idle_points.size() - 1])
	page.abort()

func test_slots_return_to_idle_and_fog_reuses_cast_and_layout() -> void:
	var page := _page()
	await get_tree().process_frame
	var session: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/combat_timeline.json"))
	page.open_session(session, {}, {}, false)
	var cast: Node2D = page.get("_arena").get_node_or_null("CombatCast")
	assert_not_null(cast)
	if cast == null:
		return
	var slots: RefCounted = page.get("_slots")
	slots.call("play_slot", "player", "skill", {"side": "player", "kind": "skill"})
	cast.call("advance_pose", 2.0)
	assert_eq((cast.get("player") as AnimatedSprite2D).animation, &"idle")
	var hero_feet: Vector2 = cast.get("player").position
	var enemy_feet: Vector2 = cast.get("enemy").position
	session["source"] = "fog"
	page.open_session(session, {}, {}, false)
	assert_eq(page.get("_arena").get_node_or_null("CombatCast"), cast)
	assert_eq(cast.get("player").position, hero_feet)
	assert_eq(cast.get("enemy").position, enemy_feet)
	assert_false((page.get("_boss_realm").get_parent() as Control).visible)
	page.abort()

func test_enemy_joints_move_independently_instead_of_rotating_a_card() -> void:
	var pose: Node2D = load("res://anim_q/battle_runtime/scripts/enemy_pose.gd").new()
	add_child_autofree(pose)
	var head := Vector2(0.40, 0.20)
	var paw := Vector2(0.40, 0.90)
	var rear_foot := Vector2(0.88, 0.98)
	assert_eq(pose.call("_joint_pose", head, 0.0, 1.0, 0.0, 0.0), head)
	assert_ne(pose.call("_joint_pose", paw, 0.0, 1.0, 0.0, 0.0), paw)
	assert_eq(pose.call("_joint_pose", rear_foot, 0.0, 1.0, 0.0, 0.0), rear_foot)
	assert_ne(pose.call("_joint_pose", head, 0.15, 0.0, 0.0, 0.0), head)
	assert_eq(pose.call("_joint_pose", paw, 0.15, 0.0, 0.0, 0.0), paw)
	assert_eq(pose.call("_joint_pose", rear_foot, 0.15, 0.0, 0.0, 0.0), rear_foot)
