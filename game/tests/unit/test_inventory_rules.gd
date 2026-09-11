extends GutTest


func _state(capacity: int = 2) -> CultivationState:
	var state := CultivationState.new()
	state.realm_id = "mortal"
	state.inventory_capacity = capacity
	return state


func test_stackable_books_share_a_slot() -> void:
	var config := AdventureConfig.from_resource()
	var state := _state(4)
	var book := config.item_by_id("book_tuna")
	InventoryRules.add_item(state, config, book, 3, GameSettings.POLICY_SKIP)
	assert_eq(state.inventory.size(), 1)
	assert_eq(state.inventory[0].count, 3)


func test_full_bag_skip_does_not_discard() -> void:
	var config := AdventureConfig.from_resource()
	var state := _state(1)
	var sword := config.item_by_id("sword_0")
	var helm := config.item_by_id("helm_0")
	InventoryRules.add_item(state, config, sword, 1, GameSettings.POLICY_SKIP)
	var result: Dictionary = InventoryRules.add_item(state, config, helm, 1, GameSettings.POLICY_SKIP)
	assert_eq(int(result.added), 0)
	assert_eq(int(result.skipped), 1)
	assert_eq(state.inventory.size(), 1)


func test_discard_lowest_makes_room() -> void:
	var config := AdventureConfig.from_resource()
	var state := _state(1)
	var white := config.item_by_id("sword_0")
	var better := config.item_by_id("sword_2")
	InventoryRules.add_item(state, config, white, 1, GameSettings.POLICY_SKIP)
	var result: Dictionary = InventoryRules.add_item(
		state,
		config,
		better,
		1,
		GameSettings.POLICY_DISCARD_LOWEST
	)
	assert_eq(int(result.added), 1)
	assert_eq(state.inventory[0].item_id, "sword_2")


func test_locked_or_equipped_cannot_be_discarded() -> void:
	var config := AdventureConfig.from_resource()
	var state := _state(2)
	var sword := config.item_by_id("sword_0")
	InventoryRules.add_item(state, config, sword, 1, GameSettings.POLICY_SKIP)
	var uid := state.inventory[0].uid
	InventoryRules.toggle_lock(state, uid)
	assert_false(InventoryRules.discard(state, uid))
	state.inventory[0].locked = false
	state.equipped.weapon = uid
	assert_false(InventoryRules.discard(state, uid))


func test_inspect_text_compares_worn_gear_and_power() -> void:
	var idle := IdleConfig.from_resource("res://resources/config/idle_rules.json")
	var config := AdventureConfig.from_resource()
	var state := _state(8)
	var white := config.item_by_id("sword_0")
	InventoryRules.add_item(state, config, white, 1, GameSettings.POLICY_SKIP)
	var before := CombatRules.player_stats(state, idle, config).power()
	var empty_text := InventoryRules.inspect_text(state, idle, config, state.inventory[0])
	assert_true(empty_text.contains("可以穿戴"), empty_text)
	assert_true(empty_text.contains("该槽位空着"), empty_text)
	assert_true(empty_text.contains("速"), empty_text)
	assert_true(empty_text.contains("词条"), empty_text)
	assert_true(empty_text.contains("装备战力"), empty_text)
	assert_true(empty_text.contains("战力"), empty_text)
	assert_true(empty_text.contains("→"), empty_text)
	state.equipped.set_uid(white.slot, state.inventory[0].uid)
	var after := CombatRules.player_stats(state, idle, config).power()
	assert_gt(after, before)
	var worn_text := InventoryRules.inspect_text(state, idle, config, state.inventory[0])
	assert_true(worn_text.contains("正在穿戴"), worn_text)
	assert_true(worn_text.contains("持平"), worn_text)
	var blue := config.item_by_id("sword_2")
	InventoryRules.add_item(state, config, blue, 1, GameSettings.POLICY_SKIP)
	var blue_text := InventoryRules.inspect_text(state, idle, config, state.inventory[1])
	assert_true(blue_text.contains("境界不足"), blue_text)
	assert_true(blue_text.contains("已穿"), blue_text)


func test_inspect_text_for_skill_book_shows_learn_delta() -> void:
	var idle := IdleConfig.from_resource("res://resources/config/idle_rules.json")
	var config := AdventureConfig.from_resource()
	var state := _state(8)
	var book := config.item_by_id("book_tuna")
	InventoryRules.add_item(state, config, book, 1, GameSettings.POLICY_SKIP)
	var text := InventoryRules.inspect_text(state, idle, config, state.inventory[0])
	assert_true(text.contains("可以参悟"), text)
	assert_true(text.contains("战力"), text)
	state.learned_skill_ids.append("tuna")
	var learned := InventoryRules.inspect_text(state, idle, config, state.inventory[0])
	assert_true(learned.contains("已入门"), learned)
	assert_true(learned.contains("小成"), learned)


func test_equipped_gear_leaves_the_bag() -> void:
	var config := AdventureConfig.from_resource()
	var state := _state(8)
	var sword := config.item_by_id("sword_0")
	var book := config.item_by_id("book_tuna")
	InventoryRules.add_item(state, config, sword, 1, GameSettings.POLICY_SKIP)
	InventoryRules.add_item(state, config, book, 1, GameSettings.POLICY_SKIP)
	state.equipped.weapon = state.inventory[0].uid
	var bag := InventoryRules.filter_stacks(state, config, "all")
	assert_eq(bag.size(), 1)
	assert_eq(bag[0].item_id, "book_tuna")
	assert_eq(InventoryRules.bag_used(state), 1)
	var gear := InventoryRules.filter_stacks(state, config, ItemDef.KIND_EQUIPMENT)
	assert_eq(gear.size(), 0)
	var books := InventoryRules.filter_stacks(state, config, ItemDef.KIND_SKILL_BOOK)
	assert_eq(books.size(), 1)


func test_equipped_items_do_not_fill_the_bag() -> void:
	var config := AdventureConfig.from_resource()
	var state := _state(1)
	var sword := config.item_by_id("sword_0")
	var helm := config.item_by_id("helm_0")
	InventoryRules.add_item(state, config, sword, 1, GameSettings.POLICY_SKIP)
	state.equipped.weapon = state.inventory[0].uid
	assert_false(InventoryRules.is_full(state))
	var result: Dictionary = InventoryRules.add_item(state, config, helm, 1, GameSettings.POLICY_SKIP)
	assert_eq(int(result.added), 1)
	assert_eq(state.inventory.size(), 2)
	assert_eq(InventoryRules.bag_used(state), 1)


func test_pill_and_material_have_detail_text() -> void:
	var idle := IdleConfig.from_resource("res://resources/config/idle_rules.json")
	var config := AdventureConfig.from_resource()
	var state := _state(8)
	var pill := config.item_by_id("pill_qi_0")
	var mat := config.item_by_id("mat_spirit_grass")
	assert_not_null(pill)
	assert_not_null(mat)
	InventoryRules.add_item(state, config, pill, 2, GameSettings.POLICY_SKIP)
	InventoryRules.add_item(state, config, mat, 1, GameSettings.POLICY_SKIP)
	var pill_text := InventoryRules.inspect_text(state, idle, config, state.inventory[0])
	assert_true(pill_text.contains("丹药"), pill_text)
	assert_true(pill_text.contains("持有"), pill_text)
	var mat_text := InventoryRules.inspect_text(state, idle, config, state.inventory[1])
	assert_true(mat_text.contains("材料"), mat_text)


func test_gear_power_uses_attack_defense_speed() -> void:
	var config := AdventureConfig.from_resource()
	var sword := config.item_by_id("sword_0")
	assert_not_null(sword)
	assert_gt(sword.speed, 0.0)
	assert_false(sword.affixes.is_empty())
	var expected := CombatStats.piece_power(sword.attack, sword.defense, sword.speed, sword.hp)
	assert_almost_eq(sword.gear_power(), expected, 0.0001)
	var boots := config.item_by_id("boots_0")
	assert_gt(boots.speed, sword.speed)
