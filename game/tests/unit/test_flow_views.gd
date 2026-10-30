extends GutTest
## 波次 / 离线弹窗 / 突破流程的纯数据模型。


func _state_with_wave() -> Dictionary:
	return {"wave": {"available": true, "stageName": "黑风岭·一", "monster": {"name": "黑风狼", "killCultivation": 4.0}, "waveSize": 3, "killsPerWave": 3, "cycleSeconds": 12.0, "progress": 5.0, "deathsInRow": 0}}


func test_wave_display_ratio_and_kills_follow_the_server_progress() -> void:
	var shown := WaveView.display(_state_with_wave())
	assert_true(shown.available)
	assert_almost_eq(float(shown.ratio), 5.0 / 12.0, 0.0001)
	assert_eq(shown.kills, 1)
	assert_string_contains(str(shown.text), "黑风狼")
	assert_string_contains(str(shown.text), "1 / 3")


func test_wave_display_advances_with_local_elapsed_and_wraps_at_the_cycle_end() -> void:
	var shown := WaveView.display(_state_with_wave(), 9.0)
	assert_almost_eq(float(shown.ratio), 2.0 / 12.0, 0.0001, "5+9=14 秒，绕过 12 秒一周期")
	assert_eq(shown.kills, 0)


func test_wave_display_without_monsters_says_so() -> void:
	var shown := WaveView.display({"wave": {"available": false}})
	assert_false(shown.available)
	assert_string_contains(str(shown.text), "没有")
	assert_false(WaveView.display({})["available"])


func test_feedback_lists_kills_cultivation_and_drops() -> void:
	var last := {"online": true, "kills": 2, "deaths": 0, "killCultivation": 8.0, "drops": [
		{"itemSlug": "gear_a", "quality": "blue", "decomposed": false, "dropped": false, "freed": [], "enhanceExp": 0},
		{"itemSlug": "gear_b", "quality": "white", "decomposed": true, "dropped": false, "freed": [], "enhanceExp": 12},
		{"itemSlug": "gear_c", "quality": "purple", "decomposed": false, "dropped": true, "freed": [], "enhanceExp": 0},
		{"itemSlug": "gear_d", "quality": "blue", "decomposed": false, "dropped": false, "freed": [{"itemSlug": "x", "enhanceExp": 3}], "enhanceExp": 3},
	]}
	var lines := WaveView.feedback(last, func(slug: String) -> String: return "名-" + slug)
	assert_eq(lines.size(), 5)
	assert_string_contains(str(lines[0].text), "×2")
	assert_string_contains(str(lines[0].text), "+8")
	assert_string_contains(str(lines[1].text), "名-gear_a")
	assert_string_contains(str(lines[2].text), "自动分解 +12")
	assert_eq(lines[3].kind, "warn")
	assert_string_contains(str(lines[4].text), "腾出格子")


func test_feedback_is_empty_when_offline_or_nothing_happened() -> void:
	assert_eq(WaveView.feedback({"online": false, "kills": 5}, func(s: String) -> String: return s).size(), 0)
	assert_eq(WaveView.feedback({"online": true, "kills": 0, "drops": []}, func(s: String) -> String: return s).size(), 0)
	assert_eq(WaveView.feedback({}, func(s: String) -> String: return s).size(), 0)


func test_offline_view_matches_the_mockup_numbers() -> void:
	var view := OfflineView.build({"id": "r1", "seconds": 33120, "countedSeconds": 28800, "hitCap": true, "offlineCapSeconds": 28800, "gained": 33120.0, "baseGained": 28800.0, "bonusGained": 4320.0, "realmName": "炼气三层"}, "青元诀", 15.0)
	assert_eq(view.away_text, "9 小时 12 分")
	assert_eq(view.counted_text, "计入 8 小时")
	assert_eq(view.bar_text, "计入 08:00:00 / 08:00:00")
	assert_eq(view.cap_note, "已满 8 小时，多出的 1 小时 12 分已作废")
	assert_eq(view.base_text, "28,800")
	assert_eq(view.bonus_text, "+4,320")
	assert_eq(view.total_text, "+33,120")
	assert_eq(view.formula_text, "28,800 + 4,320 = 33,120")
	assert_eq(view.skill_label, "技能《青元诀》")
	assert_eq(view.bonus_percent_text, "+15%")
	assert_almost_eq(float(view.bar_ratio), 1.0, 0.0001)


func test_offline_view_without_cap_or_skill() -> void:
	var view := OfflineView.build({"id": "r2", "seconds": 600, "countedSeconds": 600, "hitCap": false, "offlineCapSeconds": 28800, "gained": 600.4, "baseGained": 600.4, "bonusGained": 0.0})
	assert_eq(view.away_text, "10 分钟")
	assert_eq(view.total_text, "+600", "用服务器小数，显示时才取整")
	assert_eq(view.bonus_percent_text, "")
	assert_false(view.hit_cap)
	assert_eq(OfflineView.build(null), {})
	assert_eq(OfflineView.build({}), {})


func test_offline_view_surfaces_loot_and_bag_full_note() -> void:
	var view := OfflineView.build({
		"id": "r3", "seconds": 600, "countedSeconds": 600, "hitCap": false, "offlineCapSeconds": 28800,
		"gained": 600.0, "baseGained": 600.0, "bonusGained": 0.0,
		"loot": [
			{"itemSlug": "gear_major1_gloves_white", "quality": "white", "quantity": 1, "idle": true},
			{"itemSlug": "seed_lingcao", "quality": null, "quantity": 2, "seed": true},
		],
		"bagFullSkipped": true,
	}, "", 0.0, func(slug: String) -> String: return "白手套" if slug.begins_with("gear_") else "灵草种子")
	assert_true(view.bag_full_skipped)
	assert_eq(view.bag_full_note, "行囊已满，部分装备未入包")
	assert_eq((view.items as Array).size(), 2)
	assert_eq(str((view.items as Array)[0].text), "白手套")
	assert_eq(str((view.items as Array)[1].text), "灵草种子 ×2")
	assert_eq(int(view.item_count), 2)
	assert_eq(str(view.item_count_text), "2 件")
	var cats: Array = view.categories
	assert_eq(cats.size(), 2)
	assert_eq(str(cats[0].title), "装备")
	assert_eq(str(cats[1].title), "种子")
	var with_power := OfflineView.build({"id": "r3p", "seconds": 60, "countedSeconds": 60, "hitCap": false, "offlineCapSeconds": 28800, "gained": 60.0, "baseGained": 60.0, "bonusGained": 0.0, "loot": [], "power": 915}, "", 0.0, Callable(), -1.0)
	assert_true(bool(with_power.has_power))
	assert_eq(str(with_power.power_text), "915")
	var via_arg := OfflineView.build({"id": "r3q", "seconds": 60, "countedSeconds": 60, "hitCap": false, "offlineCapSeconds": 28800, "gained": 60.0, "baseGained": 60.0, "bonusGained": 0.0, "loot": []}, "", 0.0, Callable(), 2021.0)
	assert_true(bool(via_arg.has_power))
	assert_eq(str(via_arg.power_text), "2,021")
	var empty := OfflineView.build({"id": "r4", "seconds": 60, "countedSeconds": 60, "hitCap": false, "offlineCapSeconds": 28800, "gained": 60.0, "baseGained": 60.0, "bonusGained": 0.0, "loot": [], "bagFullSkipped": false})
	assert_eq((empty.items as Array).size(), 0)
	assert_eq(empty.bag_full_note, "")


func _break_state() -> Dictionary:
	return {
		"power": 915, "hp": 547.3, "attack": 63.4, "defense": 23.7, "speed": 24.2, "cultivation": 3300.0,
		"cultivationRate": {"gainPerTick": 1.0},
		"breakthrough": {"cost": 1800, "nextSlug": "z1", "rateBp": 10000,
			"requiredStage": {"slug": "s3", "name": "黑风岭·三", "bossName": "黑风熊王", "cleared": true},
			"preview": {"realmName": "筑基一层", "power": 2021.4, "hp": 1209.0, "attack": 146.0, "defense": 53.0, "speed": 39.0, "gainPerTick": 3.0, "ult": {"multBp": 50000}, "newStages": [{"slug": "y", "name": "幽冥古道"}]}},
	}


func test_breakthrough_view_ready_state_and_power_before_after() -> void:
	var view := BreakthroughView.build(_break_state())
	assert_true(view.can_start)
	assert_true(view.cultivation_ok)
	assert_true(view.boss_ok)
	assert_eq(view.power_now, 915)
	assert_eq(view.power_after, 2021)
	assert_eq(view.power_delta, 1106)
	assert_almost_eq(float(view.power_gain_percent), 120.87, 0.05)
	assert_eq(view.rate_percent, 100)
	assert_eq(view.rows.size(), 4)
	assert_almost_eq(float(view.rows[0].delta), 1209.0 - 547.3, 0.0001, "生命差值用小数")
	assert_eq(view.hint, "突破必定成功，超出的修为会保留")


func test_breakthrough_view_blocks_on_cultivation_then_on_boss() -> void:
	var state := _break_state()
	state.cultivation = 1231.0
	state.breakthrough.requiredStage.cleared = false
	var view := BreakthroughView.build(state)
	assert_false(view.can_start)
	assert_false(view.cultivation_ok)
	assert_eq(view.hint, "修为还差 569")
	state.cultivation = 3300.0
	view = BreakthroughView.build(state)
	assert_false(view.can_start)
	assert_eq(view.hint, "先击败首领「黑风熊王」")


func test_breakthrough_view_without_gate_or_next_realm() -> void:
	var state := _break_state()
	state.breakthrough.requiredStage = null
	assert_true(BreakthroughView.build(state).can_start)
	state.breakthrough.nextSlug = null
	var top := BreakthroughView.build(state)
	assert_false(top.has_next)
	assert_false(top.can_start)
	assert_eq(top.button_text, "已至最高境界")


func test_breakthrough_success_summary_compares_before_and_after() -> void:
	var summary := BreakthroughView.success_summary({"realmName": "炼气三层", "power": 915, "hp": 547.0, "attack": 63.0, "defense": 23.0, "speed": 24.0}, {"realmName": "筑基一层", "power": 2021, "hp": 1209.0, "attack": 146.0, "defense": 53.0, "speed": 39.0})
	assert_eq(summary.from_name, "炼气三层")
	assert_eq(summary.to_name, "筑基一层")
	assert_eq(summary.power_delta, 1106)
	assert_eq(int(summary.rows[0].delta), 662)
	assert_eq(int(summary.rows[1].delta), 83)


func test_server_address_priority_and_normalization() -> void:
	assert_eq(ServerAddress.normalize("192.168.1.20:8080"), "http://192.168.1.20:8080")
	assert_eq(ServerAddress.normalize(" https://game.example.com/ "), "https://game.example.com")
	assert_eq(ServerAddress.normalize("ftp://x"), "")
	assert_eq(ServerAddress.normalize(""), "")
	assert_eq(ServerAddress.normalize("http://"), "")
	var args := PackedStringArray(["--api-base=10.0.0.5:9000"])
	assert_eq(ServerAddress.resolve(args, "http://env:1", "http://saved:2", "http://setting:3"), "http://10.0.0.5:9000", "命令行最优先")
	assert_eq(ServerAddress.resolve(PackedStringArray(), "env:1", "http://saved:2", "http://setting:3"), "http://env:1")
	assert_eq(ServerAddress.resolve(PackedStringArray(), "", "saved:2", "http://setting:3"), "http://saved:2", "玩家保存的地址高于工程设置")
	assert_eq(ServerAddress.resolve(PackedStringArray(), "", "", "http://setting:3"), "http://setting:3")
	assert_eq(ServerAddress.resolve(PackedStringArray(), "", "not a url", ""), ServerAddress.FALLBACK)


func test_server_address_save_and_clear_roundtrip() -> void:
	ServerAddress.clear_saved()
	assert_eq(ServerAddress.save("not a url ::"), "", "不合法不保存")
	assert_eq(ServerAddress.saved(), "")
	assert_eq(ServerAddress.save("192.168.0.9:8080"), "http://192.168.0.9:8080")
	assert_eq(ServerAddress.saved(), "http://192.168.0.9:8080")
	ServerAddress.clear_saved()
	assert_eq(ServerAddress.saved(), "")
