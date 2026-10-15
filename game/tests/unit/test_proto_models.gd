extends GutTest
## 新增模型与演示服务器的纯逻辑测试：战后结算、功法/洞府展示、突破对比、背包闸门、演示接口。


func _name_of(slug: String) -> String:
	return "物:" + slug


func _fight_result(win: bool) -> Dictionary:
	return {
		"battle": {"win": win, "reason": "boss_dead" if win else "timeout", "durationSeconds": 31.5,
			"log": [
				{"t": 1.0, "side": "player", "damage": 1200.4, "targetHpAfter": 8000},
				{"t": 2.0, "side": "boss", "damage": 300.2, "targetHpAfter": 100},
				{"t": 3.0, "side": "player", "damage": 5000, "targetHpAfter": 0, "kind": "ult"},
			],
			"ultCasts": [{"t": 3.0, "readyAt": 2.0, "manual": true, "damage": 5000}, {"t": 20.0, "readyAt": 18.0, "manual": false, "damage": 5000}]},
		"drops": [{"itemSlug": "a", "quantity": 1, "quality": "blue"}, {"itemSlug": "b", "quantity": 2, "quality": "white", "dropped": true}],
		"bagFull": false,
		"reward": {"firstClear": true, "cultivation": 1500},
	}


func test_battle_summary_counts_damage_ults_and_manual_casts() -> void:
	var summary := BattleReportBuilder.summary((_fight_result(true) as Dictionary).battle)
	assert_eq(summary.dealt, 6200)
	assert_eq(summary.taken, 300)
	assert_eq(summary.ults, 1)
	assert_eq(summary.manual_ults, 1)
	assert_eq(summary.seconds, 31.5)


func test_battle_result_view_win_and_loss_texts() -> void:
	var win := BattleResultView.build(_fight_result(true), "黑风熊王", _name_of)
	assert_eq(win.title, "挑战成功")
	assert_string_contains(win.reason, "击败 黑风熊王")
	assert_eq((win.loot as Array).size(), 2)
	assert_string_contains(str(win.loot[1].text), "背包已满，没有掉落")
	assert_string_contains(str(win.notes[0]), "首通奖励")
	assert_true(bool(win.first_clear))
	var loss := BattleResultView.build(_fight_result(false), "黑风熊王", _name_of)
	assert_eq(loss.title, "挑战失败")
	assert_string_contains(loss.reason, "时间到")


func test_bag_gate_never_blocks_a_challenge_even_when_full() -> void:
	var full := BagModel.from_state(ProtoMock.state("full"), ProtoMock.content(), {})
	assert_true(full.is_full())
	assert_gt(full.auto_decomposable_count(), 0, "满包里有未强化的白/绿装备")
	for auto in [true, false]:
		var gate := full.challenge_gate(auto)
		assert_true(gate.full)
		assert_false(gate.blocked, "背包满不再拦挑战")
		assert_string_contains(GateNotice.text(gate), "新掉的装备不会入包")
	var ready := BagModel.from_state(ProtoMock.state("ready"), ProtoMock.content(), {})
	assert_false(ready.challenge_gate(false).full)


func test_equipment_upgrades_only_when_the_spare_is_stronger() -> void:
	var bag := BagModel.from_state(ProtoMock.state("ready"), ProtoMock.content(), {})
	var ids := EquipModel.best_upgrades(bag)
	assert_gt(ids.size(), 0)
	var fresh := BagModel.from_state(ProtoMock.state("fresh"), ProtoMock.content(), {})
	assert_eq(EquipModel.best_upgrades(fresh).size(), 0)


func test_skill_view_marks_the_running_skill_and_lists_cards() -> void:
	var view := SkillView.build(ProtoMock.state("ready"), ProtoMock.content())
	assert_gt((view.cards as Array).size(), 0)
	var running := (view.cards as Array).filter(func(c: Dictionary) -> bool: return str(c.status) == "running")
	assert_eq(running.size(), 1)
	assert_eq(SkillView.running_name(ProtoMock.state("ready"), ProtoMock.content()), "青元诀")
	assert_eq(SkillView.running_name(ProtoMock.state("fresh"), ProtoMock.content()), "")


func test_cave_is_static_display_data() -> void:
	assert_eq(CaveView.buildings().size(), 5)
	assert_eq(CaveView.level_text(CaveView.buildings()[0]), "Lv.5")
	assert_string_contains(CaveView.output_text(CaveView.buildings()[0]), "+6/时")


func test_breakthrough_unlocks_list_changes_from_the_preview() -> void:
	var state := ProtoMock.state("ready")
	var list := BreakthroughView.unlocks(state, ProtoMock.content())
	assert_gt(list.size(), 0)
	for row in list:
		assert_ne(str(row.text), "")


func test_preview_includes_current_gear_so_before_after_are_comparable() -> void:
	var state := ProtoMock.state("ready")
	var preview: Dictionary = state.breakthrough.preview
	assert_gt(float(preview.power), float(state.power), "突破后的战力 > 现在")
	var bare := ProtoMock.realm_snapshot(str(state.breakthrough.nextSlug))
	assert_gt(float(preview.attack), float(bare.attack), "预览 = 裸属性 + 当前装备")


func test_mock_breakthrough_enforces_the_gate_stage_then_the_cost() -> void:
	var content := ProtoMock.content()
	var state := ProtoMock.state("gate")
	var denied := ProtoMock.handle("/api/v1/me/breakthrough", {}, state, content)
	assert_eq(int(denied.code), 409)
	assert_eq(str(denied.error.code), "STAGE_REQUIRED")
	state.breakthrough.requiredStage.cleared = true
	state["cultivation"] = 1.0
	assert_eq(str(ProtoMock.handle("/api/v1/me/breakthrough", {}, state, content).error.code), "NOT_ENOUGH_CULTIVATION")
	state["cultivation"] = 99999.0
	var power_before := int(state.power)
	var done := ProtoMock.handle("/api/v1/me/breakthrough", {}, state, content)
	assert_eq(int(done.code), 200)
	assert_true(bool(done.result.success))
	assert_gt(int(done.state.power), power_before)


func test_mock_ack_and_idle_stage() -> void:
	var content := ProtoMock.content()
	var state := ProtoMock.state("ready")
	var report_id := str(state.offlineReport.id)
	var ack := ProtoMock.handle("/api/v1/me/offline-reports/%s/ack" % report_id, {}, state, content)
	assert_true(bool(ack.acknowledged))
	assert_null(state.offlineReport)
	var selectable: Array = state.wave.selectable
	if selectable.size() > 0:
		var slug := str(selectable[0].slug)
		var idle := ProtoMock.handle("/api/v1/me/idle-stage", {"stageSlug": slug}, state, content)
		assert_eq(int(idle.code), 200)
		assert_eq(str(state.wave.chosenStageSlug), slug)


func test_mock_challenge_with_a_full_bag_is_not_refused_and_the_drop_is_not_dropped() -> void:
	var content := ProtoMock.content()
	var state := ProtoMock.state("full")
	var slug := str(state.breakthrough.requiredStage.slug)
	for auto in [false, true]:
		state["autoDecompose"] = auto
		var ok := ProtoMock.handle("/api/v1/me/stages/%s/challenge" % slug, {"ultTaps": []}, state, content)
		assert_eq(int(ok.code), 200, "满包也能挑战")
		assert_false(ok.has("freedBeforeFight"))
		if bool(ok.battle.win):
			assert_true(bool(ok.bagFull))
			assert_true(bool(ok.drops[0].get("dropped", false)))


func test_top_bar_shows_realm_power_and_cultivation_only() -> void:
	var bar := TopBar.new()
	add_child_autofree(bar)
	bar.bind({"realmName": "炼气三层", "power": 12345, "cultivation": 1200.0, "breakthrough": {"cost": 3600.0, "nextSlug": "lianqi_4"}})
	assert_eq(bar.realm_text(), "炼气三层")
	assert_eq(bar.power_text(), "战力 12,345")
	assert_eq(bar.cultivation_text(), "1,200 / 3,600")
