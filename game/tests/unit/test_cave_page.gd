extends GutTest
## 洞府 L0+L1 场所硬接：庭院三热点、强化进场所页再走行囊、药园子页可进。


func test_enhance_hotspot_opens_place_then_emits() -> void:
	var page := CavePage.new()
	add_child_autofree(page)
	page.bind({
		"dongfu": {
			"plotCount": 4,
			"alchemyQueueLength": 2,
			"plots": [],
			"alchemy": [],
			"claimable": {"plots": 0, "alchemy": 0},
		},
		"items": [],
		"spiritStones": 10,
	}, {"globals": {"dongfu": {"plotCount": 4, "alchemyQueueLength": 2, "seeds": [], "recipes": []}}, "items": []})
	var enter := page.find_child("Enter_enhance", true, false) as BaseButton
	assert_not_null(enter, "L0 有强化热点")
	enter.pressed.emit()
	assert_eq(page.mode(), "enhance", "强化进场所页")
	watch_signals(page)
	var rune := page.find_child("EnhanceBtn", true, false) as BaseButton
	assert_not_null(rune, "场所页有强化符文石")
	rune.pressed.emit()
	assert_signal_emitted(page, "enhance_entry_requested")


func test_garden_card_opens_subpage() -> void:
	var page := CavePage.new()
	add_child_autofree(page)
	var plots := []
	for i in 4:
		plots.append({"slot": i, "seedSlug": null, "herbSlug": null, "plantedAt": null, "matureAt": null, "status": "empty"})
	page.bind({
		"dongfu": {
			"plotCount": 4,
			"alchemyQueueLength": 2,
			"plots": plots,
			"alchemy": [],
			"claimable": {"plots": 0, "alchemy": 0},
		},
		"items": [{"id": "s1", "itemSlug": "seed_lingcao", "quantity": 1, "isStack": true}],
		"spiritStones": 0,
	}, {
		"globals": {"dongfu": {
			"plotCount": 4,
			"alchemyQueueLength": 2,
			"seeds": [{"seedSlug": "seed_lingcao", "herbSlug": "herb_lingcao", "growSeconds": 60}],
			"recipes": [],
		}},
		"items": [{"slug": "seed_lingcao", "displayName": "灵草种子"}, {"slug": "herb_lingcao", "displayName": "灵草"}],
	})
	var enter := page.find_child("Enter_garden", true, false) as BaseButton
	assert_not_null(enter)
	enter.pressed.emit()
	assert_eq(page.mode(), "garden")
	assert_not_null(page.find_child("GardenClaimAll", true, false))
	assert_not_null(page.find_child("Plot_0", true, false))
	assert_not_null(page.find_child("Upgrade_garden", true, false))
	assert_not_null(page.find_child("SeedPicker", true, false))


func test_allocate_and_upgrade_emit_actions() -> void:
	var page := CavePage.new()
	add_child_autofree(page)
	page.bind({
		"dongfu": {
			"plotCount": 4,
			"alchemyQueueLength": 2,
			"plots": [],
			"alchemy": [],
			"claimable": {"plots": 0, "alchemy": 0},
			"allocation": {"garden": 1, "alchemy": 0},
			"servantTotal": 4,
			"woodCount": 32,
			"woodItemSlug": "wood_lingmu",
			"timeScale": {"garden": 0.95, "alchemy": 1},
			"gardenLevel": 1,
			"alchemyLevel": 1,
			"upgrades": {
				"garden": {"level": 1, "canUpgrade": true, "reason": "", "next": {"toLevel": 2, "wood": 8, "spiritStones": 0, "bonus": 1}},
				"alchemy": {"level": 1, "canUpgrade": false, "reason": "灵木不足", "next": {"toLevel": 2, "wood": 8, "spiritStones": 0, "bonus": 1}},
			},
		},
		"items": [],
		"spiritStones": 0,
	}, {"globals": {"dongfu": {"plotCount": 4, "alchemyQueueLength": 2, "seeds": [], "recipes": []}}, "items": [{"slug": "wood_lingmu", "displayName": "灵木"}]})
	var plus := page.find_child("AllocPlus_garden", true, false) as BaseButton
	assert_not_null(plus)
	assert_false(plus.disabled)
	watch_signals(page)
	plus.pressed.emit()
	assert_signal_emitted(page, "action_requested")
	# 升级在药园 L1
	var enter := page.find_child("Enter_garden", true, false) as BaseButton
	enter.pressed.emit()
	var upgrade := page.find_child("Upgrade_garden", true, false) as BaseButton
	assert_not_null(upgrade)
	assert_false(upgrade.disabled)
	upgrade.pressed.emit()
	assert_signal_emit_count(page, "action_requested", 2)


func test_enhance_ring_binds_worn_gear_and_selects_heart() -> void:
	var page := CavePage.new()
	add_child_autofree(page)
	var content := UiMock.content()
	# 洞府字段保证 L0 可进强化场所
	content["globals"]["dongfu"] = {"plotCount": 4, "alchemyQueueLength": 2, "seeds": [], "recipes": []}
	page.bind({
		"dongfu": {
			"plotCount": 4,
			"alchemyQueueLength": 2,
			"plots": [],
			"alchemy": [],
			"claimable": {"plots": 0, "alchemy": 0},
		},
		"items": [
			{"id": "w1", "itemSlug": "sword_b", "equippedSlot": "weapon", "isStack": false, "quantity": 1, "enhanceLevel": 2, "breakLevel": 0},
			{"id": "h1", "itemSlug": "helm_g", "equippedSlot": "helmet", "isStack": false, "quantity": 1, "enhanceLevel": 0, "breakLevel": 0},
			{"id": "c1", "itemSlug": "robe_g", "equippedSlot": "clothes", "isStack": false, "quantity": 1, "enhanceLevel": 1, "breakLevel": 0},
		],
		"spiritStones": 0,
		"enhanceExp": 999,
	}, content)
	var enter := page.find_child("Enter_enhance", true, false) as BaseButton
	assert_not_null(enter)
	enter.pressed.emit()
	assert_eq(page.mode(), "enhance")
	assert_not_null(page.find_child("EqRing_0", true, false), "武器环格")
	assert_not_null(page.find_child("EqRing_1", true, false), "头冠环格")
	assert_eq(page.selected_enhance_id(), "w1", "默认预选可强化的武器")
	assert_not_null(page.find_child("ArrayHeart", true, false))
	var helm := page.find_child("EqRing_1", true, false) as BaseButton
	helm.pressed.emit()
	assert_eq(page.selected_enhance_id(), "h1", "点环切换阵心目标")
	watch_signals(page)
	var rune := page.find_child("EnhanceBtn", true, false) as BaseButton
	rune.pressed.emit()
	assert_signal_emitted(page, "enhance_entry_requested")
