extends GutTest
## 客户端预演（BossFight）必须和服务端 simulateBossFight 逐项一致：
## fixtures/boss_fight_cases.json 由 tools/sim/gen_boss_fixture.ts 用服务端代码生成。

const FIXTURE := "res://tests/fixtures/boss_fight_cases.json"


func _cases() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return parsed as Array if parsed is Array else []


func _fight(row: Dictionary) -> BossFight:
	var fight := BossFight.new()
	var config: Dictionary = row.config
	fight.setup(row.player, row.boss, float(config.defenseConstant), float(config.timeLimitSeconds), row.ult if row.ult != null else {})
	return fight


## 按点击时间表回放：到点前推进，再点一下。
func _replay(fight: BossFight, taps: Array) -> void:
	for tap_time in taps:
		fight.advance_to(float(tap_time))
		fight.tap()
	fight.advance_to(1000.0)


func test_fixture_is_present_and_has_cases_where_tap_timing_matters() -> void:
	var cases := _cases()
	assert_gt(cases.size(), 30, "fixture 缺失或太少")


func test_every_server_case_replays_identically() -> void:
	var mismatches: Array[String] = []
	for row in _cases():
		var fight := _fight(row)
		_replay(fight, row.taps)
		var want: Dictionary = row.expect
		var label := str(row.name)
		if fight.win != bool(want.win) or fight.reason != str(want.reason):
			mismatches.append("%s: 胜负 %s/%s 应为 %s/%s" % [label, fight.win, fight.reason, want.win, want.reason])
			continue
		if absf(fight.duration - float(want.durationSeconds)) > 0.0001:
			mismatches.append("%s: 用时 %.5f 应为 %.5f" % [label, fight.duration, float(want.durationSeconds)])
		if fight.log.size() != int(want.eventCount):
			mismatches.append("%s: 事件数 %d 应为 %d" % [label, fight.log.size(), int(want.eventCount)])
		var casts: Array = want.casts
		if fight.casts.size() != casts.size():
			mismatches.append("%s: 大招次数 %d 应为 %d" % [label, fight.casts.size(), casts.size()])
			continue
		for index in casts.size():
			var mine: Dictionary = fight.casts[index]
			var theirs: Dictionary = casts[index]
			if absf(float(mine.t) - float(theirs.t)) > 0.0001 or bool(mine.manual) != bool(theirs.manual) or absf(float(mine.damage) - float(theirs.damage)) > 0.0001:
				mismatches.append("%s: 第 %d 次大招 t=%.5f manual=%s dmg=%.3f 应为 t=%.5f manual=%s dmg=%.3f" % [label, index + 1, float(mine.t), mine.manual, float(mine.damage), float(theirs.t), theirs.manual, float(theirs.damage)])
		var last: Variant = want.lastEvent
		if last != null and not fight.log.is_empty():
			var mine_last: Dictionary = fight.log[fight.log.size() - 1]
			if absf(float(mine_last.targetHpAfter) - float((last as Dictionary).targetHpAfter)) > 0.0001:
				mismatches.append("%s: 最后一击后的血量 %.4f 应为 %.4f" % [label, float(mine_last.targetHpAfter), float((last as Dictionary).targetHpAfter)])
	assert_eq(mismatches.size(), 0, "\n".join(mismatches))


func test_frame_stepping_gives_the_same_result_as_one_jump() -> void:
	for row in _cases():
		if not (row.taps as Array).is_empty():
			continue
		var jump := _fight(row)
		jump.advance_to(1000.0)
		var frames := _fight(row)
		var clock := 0.0
		while not frames.finished and clock < 60.0:
			clock += 1.0 / 60.0
			frames.advance_to(clock)
		assert_eq(frames.win, jump.win, str(row.name))
		assert_almost_eq(frames.duration, jump.duration, 0.0001, str(row.name))
		assert_eq(frames.casts.size(), jump.casts.size(), str(row.name))


func test_tap_before_ready_is_ignored_and_ready_tap_casts_now() -> void:
	var fight := BossFight.new()
	fight.setup({"attack": 50, "defense": 10, "hp": 5000, "interval": 1.0}, {"attack": 1, "defense": 10, "hp": 50000, "interval": 1.0}, 1.0, 45.0, {"multBp": 40000, "cooldownSeconds": 20, "firstCooldownSeconds": 8, "autoCastWindowSeconds": 2})
	fight.advance_to(3.0)
	assert_false(fight.ult_ready())
	assert_false(fight.tap(), "冷却没好，点击无效")
	assert_eq(fight.taps.size(), 0)
	assert_almost_eq(fight.ult_progress(), 3.0 / 8.0, 0.0001)
	fight.advance_to(8.5)
	assert_true(fight.ult_ready())
	assert_almost_eq(fight.ult_auto_left(), 1.5, 0.0001)
	assert_true(fight.tap())
	assert_eq(fight.casts.size(), 1)
	assert_true(bool(fight.casts[0].manual))
	assert_almost_eq(float(fight.casts[0].t), 8.5, 0.0001)
	assert_false(fight.ult_ready(), "释放后重新冷却")
	assert_almost_eq(fight.ult_cooldown_left(), 20.0, 0.001)
	assert_false(fight.tap(), "冷却中再点无效")


func test_auto_cast_happens_when_the_window_ends() -> void:
	var fight := BossFight.new()
	fight.setup({"attack": 50, "defense": 10, "hp": 5000, "interval": 1.0}, {"attack": 1, "defense": 10, "hp": 50000, "interval": 1.0}, 1.0, 45.0, {"multBp": 50000, "cooldownSeconds": 18, "firstCooldownSeconds": 8, "autoCastWindowSeconds": 2})
	fight.advance_to(9.99)
	assert_eq(fight.casts.size(), 0)
	fight.advance_to(10.0)
	assert_eq(fight.casts.size(), 1)
	assert_false(bool(fight.casts[0].manual))
	assert_almost_eq(float(fight.casts[0].t), 10.0, 0.0001)
	assert_eq(fight.upload_taps().size(), 0, "自动释放不上报点击")


func test_without_ult_the_fight_is_plain_auto_attack() -> void:
	var fight := BossFight.new()
	fight.setup({"attack": 50, "defense": 10, "hp": 5000, "interval": 1.0}, {"attack": 1, "defense": 10, "hp": 200, "interval": 1.0}, 1.0, 45.0, {})
	assert_false(fight.has_ult())
	assert_false(fight.tap())
	fight.advance_to(60.0)
	assert_true(fight.win)
	assert_eq(fight.casts.size(), 0)
	assert_eq(fight.ult_progress(), 0.0)


func test_uses_server_decimals_not_integers() -> void:
	var fight := BossFight.new()
	fight.setup({"attack": 63.4, "defense": 23.7, "hp": 547.3, "interval": 1.5}, {"attack": 34, "defense": 19, "hp": 1500, "interval": 1.6}, 1.0, 45.0, {})
	assert_almost_eq(fight.player_damage(), 63.4 * 63.4 / (63.4 + 19.0), 0.000001)
	assert_ne(fight.player_damage(), floorf(fight.player_damage()))
	assert_almost_eq(fight.player_max_hp, 547.3, 0.000001)


func test_from_state_reads_content_combat_rules_and_the_first_boss() -> void:
	var state := {"attack": 63.4, "defense": 23.7, "hp": 547.3, "interval": 1.5, "ult": {"multBp": 40000, "cooldownSeconds": 20, "firstCooldownSeconds": 8, "autoCastWindowSeconds": 2}}
	var content := {"globals": {"combat": {"defenseConstant": 2.0, "timeLimitSeconds": 30}}}
	var stage := {"bosses": [{"name": "熊王", "attack": 34, "defense": 19, "hp": 1500, "interval": 1.6}]}
	var fight := BossFight.from_state(state, content, stage)
	assert_not_null(fight)
	assert_eq(fight.time_limit, 30.0)
	assert_eq(fight.defense_constant, 2.0)
	assert_true(fight.has_ult())
	assert_null(BossFight.from_state(state, content, {"bosses": []}))


func test_time_limit_ends_the_fight_as_timeout() -> void:
	var fight := BossFight.new()
	fight.setup({"attack": 5, "defense": 40, "hp": 9000, "interval": 2.0}, {"attack": 3, "defense": 30, "hp": 100000, "interval": 2.0}, 1.0, 45.0, {})
	fight.advance_to(46.0)
	assert_true(fight.finished)
	assert_false(fight.win)
	assert_eq(fight.reason, "timeout")
	assert_eq(fight.duration, 45.0)
