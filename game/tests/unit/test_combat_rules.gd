extends GutTest


func _player(attack: float, defense: float, hp: float, interval: float = 1.5) -> CombatStats:
	var stats := CombatStats.new()
	stats.attack = attack
	stats.defense = defense
	stats.hp = hp
	stats.interval = interval
	return stats


func test_time_to_kill_and_die_are_formula_based() -> void:
	var player := _player(10, 6, 50, 1.5)
	var monster := _player(6, 2, 18, 1.8)
	var kill := CombatRules.time_to_kill(player, monster)
	var die := CombatRules.time_to_die(player, monster)
	assert_gt(kill, 0.0)
	assert_gt(die, kill)
	assert_almost_eq(kill, 18.0 / ((10.0 - 2.0 * 0.4) / 1.5), 0.0001)


func test_stronger_monster_forces_retreat() -> void:
	var player := _player(4, 1, 10, 1.5)
	var monster := _player(80, 40, 400, 1.0)
	assert_true(CombatRules.time_to_die(player, monster) <= CombatRules.time_to_kill(player, monster))


func test_session_offline_combat_fills_bag_once() -> void:
	var clock := TimeService.new()
	clock.set_unix(5_000)
	var stamp := str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	var save := SaveService.new(
		"user://tests/adv_%s.json" % stamp,
		"user://tests/adv_%s.bak.json" % stamp,
		"user://tests/adv_%s.json.tmp" % stamp
	)
	var first := CultivationSession.new(clock, save, null, "0.1.6")
	assert_true(first.start())
	assert_eq(first.state.inventory.size(), 0)
	clock.set_unix(5_000 + 120)
	var second := CultivationSession.new(clock, save, null, "0.1.6")
	assert_true(second.start())
	assert_gt(second.last_offline_result.combat_kills, 0)
	var bag_size := second.state.inventory.size()
	var third := CultivationSession.new(clock, save, null, "0.1.6")
	assert_true(third.start())
	assert_eq(third.last_offline_result.combat_kills, 0)
	assert_eq(third.state.inventory.size(), bag_size)


func test_equip_and_learn_change_combat_power() -> void:
	var clock := TimeService.new()
	clock.set_unix(8_000)
	var stamp := str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	var save := SaveService.new(
		"user://tests/gear_%s.json" % stamp,
		"user://tests/gear_%s.bak.json" % stamp,
		"user://tests/gear_%s.json.tmp" % stamp
	)
	var session := CultivationSession.new(clock, save, null, "0.1.6")
	assert_true(session.start())
	var before := session.player_stats().power()
	var item := session.adventure.item_by_id("sword_0")
	assert_not_null(item)
	InventoryRules.add_item(session.state, session.adventure, item, 1, GameSettings.POLICY_SKIP)
	var uid := session.state.inventory[0].uid
	assert_eq(session.equip_item(uid), "")
	assert_gt(session.player_stats().power(), before)
	var book := session.adventure.item_by_id("book_tuna")
	InventoryRules.add_item(session.state, session.adventure, book, 1, GameSettings.POLICY_SKIP)
	var book_uid := session.state.inventory[session.state.inventory.size() - 1].uid
	assert_eq(session.learn_skill_from(book_uid), "")
	assert_true(session.state.learned_skill_ids.has("tuna"))
	assert_true(session.learn_skill_from(book_uid).contains("已学会") or not InventoryRules.find_stack(session.state, book_uid))


func test_next_stage_requires_realm_and_power() -> void:
	var clock := TimeService.new()
	clock.set_unix(9_000)
	var stamp := str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	var save := SaveService.new(
		"user://tests/gate_%s.json" % stamp,
		"user://tests/gate_%s.bak.json" % stamp,
		"user://tests/gate_%s.json.tmp" % stamp
	)
	var session := CultivationSession.new(clock, save, null, "0.1.6")
	assert_true(session.start())
	assert_false(session.can_challenge_next())
	var reason := session.challenge_next()
	assert_true(reason.contains("战力不足") or reason.contains("境界不足"), reason)
	assert_eq(session.state.current_stage_id, "grove")
