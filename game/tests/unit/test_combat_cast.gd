extends GutTest

func _page() -> TimelineBattlePage:
	var page := TimelineBattlePage.new()
	page.size = Vector2(1032, 2276)
	add_child_autofree(page)
	return page

func test_ready_uses_unified_actors_centered_without_fallback_cast() -> void:
	var page := _page()
	await get_tree().process_frame
	page.open_stage({}, {}, {"slug": "test", "bosses": [{"name": "雾境守卫", "artKey": "bear"}]}, {}, "")
	await get_tree().process_frame
	var arena: Control = page.get("_arena")
	assert_null(arena.get_node_or_null("CombatCast"), "actor.tscn takes over so CombatCast is not also created")
	var player: Node2D = arena.get_node_or_null("UnifiedPlayerActor")
	var boss: Node2D = arena.get_node_or_null("UnifiedBossActor")
	assert_not_null(player, "player actor")
	assert_not_null(boss, "boss actor")
	if player == null or boss == null:
		return
	assert_almost_eq((player.position.x + boss.position.x) / 2.0, arena.size.x / 2.0, 2.0)
	assert_almost_eq(player.position.y, boss.position.y, 0.1)
	assert_lt(player.position.y, arena.size.y * 0.75, "not bottom-left")
	assert_gt(player.position.x, 10.0)
	var hero: Node2D = player.get("fighter")
	assert_eq(hero.get("sprite").sprite_frames.get_frame_count("idle"), 1)
	var before_y: float = hero.get("sprite").position.y
	hero.call("advance", 0.65)
	assert_ne(hero.get("sprite").position.y, before_y, "idle uses code-driven breath")
	assert_false((page.get("_fx").get("boss") as CanvasItem).visible)
	page.abort()

func test_outgoing_attack_uses_sheet_and_recovers_to_idle() -> void:
	var page := _page()
	await get_tree().process_frame
	page.open_stage({}, {}, {"slug": "test", "bosses": [{"name": "雾境守卫", "artKey": "bear"}]}, {}, "")
	await get_tree().process_frame
	var arena: Control = page.get("_arena")
	var player: Node2D = arena.get_node_or_null("UnifiedPlayerActor")
	var boss: Node2D = arena.get_node_or_null("UnifiedBossActor")
	assert_not_null(player)
	assert_not_null(boss)
	if player == null or boss == null:
		return
	var slots: RefCounted = page.get("_slots")
	var hero: Node2D = player.get("fighter")
	var home: Vector2 = hero.position
	slots.call("play_slot", "player", "attack", {"side": "player", "kind": "attack"})
	player.call("advance_presentation", 0.21)
	assert_eq(hero.state, "attack")
	assert_eq(hero.get("sprite").animation, &"普通攻击")
	assert_gt(hero.get("sprite").frame, 0)
	assert_ne(hero.position, home, "code-driven attack lunge")
	player.call("advance_presentation", 1.0)
	assert_eq(hero.state, "idle")
	var enemy: Node2D = boss.get("fighter")
	var enemy_home: Vector2 = enemy.position
	slots.call("play_slot", "boss", "attack", {"side": "boss", "kind": "attack"})
	boss.call("advance_presentation", 0.21)
	assert_eq(enemy.state, "attack")
	assert_ne(enemy.position, enemy_home, "boss also uses velocity")
	page.abort()

func test_slots_return_to_idle_and_fog_reuses_actors() -> void:
	var page := _page()
	await get_tree().process_frame
	var session: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/combat_timeline.json"))
	page.open_session(session, {}, {}, false)
	var arena: Control = page.get("_arena")
	var player: Node2D = arena.get_node_or_null("UnifiedPlayerActor")
	assert_not_null(player)
	if player == null:
		return
	var slots: RefCounted = page.get("_slots")
	slots.call("play_slot", "player", "skill", {"side": "player", "kind": "skill"})
	player.call("advance_presentation", 3.0)
	assert_eq(player.get("fighter").state, "idle")
	var hero_feet: Vector2 = player.position
	var boss: Node2D = arena.get_node_or_null("UnifiedBossActor")
	var enemy_feet: Vector2 = boss.position
	session["source"] = "fog"
	page.open_session(session, {}, {}, false)
	assert_eq(arena.get_node_or_null("UnifiedPlayerActor"), player)
	assert_eq(player.position, hero_feet)
	assert_eq(boss.position, enemy_feet)
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
