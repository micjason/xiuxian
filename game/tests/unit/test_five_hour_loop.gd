extends GutTest


func _idle() -> IdleConfig:
	return IdleConfig.from_resource("res://resources/config/idle_rules.json")


func _adventure() -> AdventureConfig:
	return AdventureConfig.from_resource()


func _session(clock: TimeService = null) -> CultivationSession:
	if clock == null:
		clock = TimeService.new()
		clock.set_unix(20_000)
	var stamp := str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	var save := SaveService.new(
		"user://tests/five_%s.json" % stamp,
		"user://tests/five_%s.bak.json" % stamp,
		"user://tests/five_%s.json.tmp" % stamp
	)
	var session := CultivationSession.new(clock, save, null, "0.1.14")
	assert_true(session.start())
	return session


func _add(session: CultivationSession, item_id: String, count: int = 1) -> ItemStack:
	var item := session.adventure.item_by_id(item_id)
	assert_not_null(item, item_id)
	InventoryRules.add_item(session.state, session.adventure, item, count, GameSettings.POLICY_SKIP)
	return session.state.inventory[session.state.inventory.size() - 1]


func test_same_name_merge_raises_stats_and_rejects_worn() -> void:
	var session := _session()
	var first := _add(session, "sword_0")
	var second := _add(session, "sword_0")
	var item := session.adventure.item_by_id("sword_0")
	assert_eq(session.merge_item(first.uid), "")
	assert_eq(first.merge_level, 1)
	assert_null(InventoryRules.find_stack(session.state, second.uid))
	var live := item.to_stats(first)
	assert_almost_eq(live.attack, item.attack * 1.12, 0.0001)
	assert_eq(session.equip_item(first.uid), "")
	_add(session, "sword_0")
	assert_true(session.merge_item(first.uid).contains("穿戴"))


func test_shortfall_wall_can_fail_when_power_is_enough() -> void:
	var idle := _idle()
	var adventure := _adventure()
	var state := CultivationState.new()
	state.realm_id = "qi_early"
	var stage := adventure.stage_by_id("boar_slope")
	var stats := CombatStats.new()
	stats.attack = 10.0
	stats.defense = 40.0
	stats.hp = 200.0
	assert_gt(stats.power() + 0.0001, stage.min_power)
	var reason := CombatRules.enter_reason(state, idle, stage, stats, false)
	assert_true(reason.contains("缺攻"), reason)
	stats.attack = 18.0
	assert_eq(CombatRules.enter_reason(state, idle, stage, stats, false), "")
	state.realm_id = "qi_mid"
	var brook := adventure.stage_by_id("stone_brook")
	stats.speed = 1.0
	stats.attack = 40.0
	stats.defense = 40.0
	assert_true(CombatRules.enter_reason(state, idle, brook, stats, false).contains("缺速"))


func test_three_layers_unlock_by_kills() -> void:
	var session := _session()
	var stage := session.current_stage()
	assert_eq(session.select_layer(StageLayer.INNER), "%s 深处未开，外围还需斩杀 %d。" % [
		stage.display_name,
		StageLayer.INNER_KILLS,
	])
	session.state.add_kills(stage.id, StageLayer.OUTER, StageLayer.INNER_KILLS)
	assert_eq(session.select_layer(StageLayer.INNER), "")
	assert_eq(session.state.current_layer(), StageLayer.INNER)
	assert_true(session.select_layer(StageLayer.BOSS).contains("头目未开"))
	session.state.add_kills(stage.id, StageLayer.INNER, StageLayer.BOSS_KILLS)
	assert_eq(session.select_layer(StageLayer.BOSS), "")
	assert_eq(session.state.current_layer(), StageLayer.BOSS)
	var combat := CombatRules.settle(session.state, session.config, session.adventure, 30)
	assert_gt(combat.kills, 0)
	assert_gt(session.state.kills_of(stage.id, StageLayer.BOSS), 0)


func test_same_tier_set_bonus_scales_damage() -> void:
	var idle := _idle()
	var adventure := _adventure()
	var state := CultivationState.new()
	state.realm_id = "mortal"
	state.inventory_capacity = 16
	for item_id in ["sword_0", "helm_0", "robe_0"]:
		var item := adventure.item_by_id(item_id)
		InventoryRules.add_item(state, adventure, item, 1, GameSettings.POLICY_SKIP)
		state.equipped.set_uid(item.slot, state.inventory[state.inventory.size() - 1].uid)
	var three := CombatRules.player_stats(state, idle, adventure)
	assert_almost_eq(three.damage_dealt_scale, 1.06, 0.0001)
	assert_almost_eq(three.damage_taken_scale, 1.0, 0.0001)
	for item_id in ["boots_0", "jade_0"]:
		var item := adventure.item_by_id(item_id)
		InventoryRules.add_item(state, adventure, item, 1, GameSettings.POLICY_SKIP)
		state.equipped.set_uid(item.slot, state.inventory[state.inventory.size() - 1].uid)
	var five := CombatRules.player_stats(state, idle, adventure)
	assert_almost_eq(five.damage_dealt_scale, 1.12, 0.0001)
	assert_almost_eq(five.damage_taken_scale, 0.92, 0.0001)


func test_skill_minor_rank_pills_and_temper() -> void:
	var clock := TimeService.new()
	clock.set_unix(30_000)
	var session := _session(clock)
	var book := _add(session, "book_tuna")
	assert_eq(session.learn_skill_from(book.uid), "")
	assert_eq(session.state.skill_rank_of("tuna"), 1)
	var after_intro := session.player_stats().attack
	_add(session, "book_tuna", 2)
	var leftover := InventoryRules.find_stack(session.state, session.state.inventory[session.state.inventory.size() - 1].uid)
	assert_eq(session.learn_skill_from(leftover.uid), "")
	assert_eq(session.state.skill_rank_of("tuna"), 2)
	assert_gt(session.player_stats().attack, after_intro)
	var pill := _add(session, "pill_qi_0")
	var base_rate := session.current_realm().gain_per_second
	assert_eq(session.consume_pill(pill.uid), "")
	assert_almost_eq(session.cultivate_rate(), base_rate * 1.15, 0.0001)
	var body := _add(session, "pill_body_0")
	var before_def := session.player_stats().defense
	assert_eq(session.consume_pill(body.uid), "")
	assert_almost_eq(session.player_stats().defense, before_def * 1.2, 0.0001)
	var gear := _add(session, "sword_0")
	_add(session, "mat_spirit_grass", 3)
	_add(session, "mat_beast_bone", 1)
	var sword := session.adventure.item_by_id("sword_0")
	assert_eq(session.temper_item(gear.uid), "")
	assert_true(gear.tempered)
	assert_almost_eq(sword.to_stats(gear).attack, sword.attack + 0.8, 0.0001)
	clock.set_unix(30_000 + 601)
	session.tick_online()
	assert_eq(session.state.qi_pill_until, 0)
	assert_eq(session.state.body_pill_until, 0)
