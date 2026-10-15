extends GutTest
## 战力构成、文字战报生成、本地物品标记。


func test_power_breakdown_parts_cover_all_stats_and_ratios_sum_to_one() -> void:
	var state := UiMock.state()
	var result := PowerBreakdown.compute(state, UiMock.content())
	assert_eq(result.parts.size(), 3)
	var ratio := 0.0
	for part in result.parts:
		ratio += float(part.ratio)
	assert_almost_eq(ratio, 1.0, 0.001)
	assert_eq(int(result.total), int(state.power))
	assert_eq(int(result.other), 0, "演示数据的战力就是按权重算的")


func test_power_breakdown_reports_other_bonus_instead_of_hiding_it() -> void:
	var state := UiMock.state()
	state["power"] = int(state.power) + 50
	var result := PowerBreakdown.compute(state, UiMock.content())
	assert_eq(int(result.other), 50)


func test_power_breakdown_falls_back_to_scheme_weights() -> void:
	var result := PowerBreakdown.compute({"attack": 100, "defense": 0, "hp": 0, "speed": 0, "power": 470}, {})
	assert_eq(int(result.computed), 470)
	assert_eq(int(result.parts[0].value), 470)


func test_battle_report_has_rounds_damage_and_result() -> void:
	var battle := {
		"win": true, "reason": "win", "durationSeconds": 2.5,
		"log": [
			{"t": 1.0, "side": "player", "damage": 100, "targetHpAfter": 900},
			{"t": 1.4, "side": "boss", "damage": 20, "targetHpAfter": 480},
			{"t": 2.5, "side": "player", "damage": 900, "targetHpAfter": 0},
		],
	}
	var lines := BattleReportBuilder.build(battle, "枯木妖", 500, 1000)
	var rounds := 0
	var dealt := 0
	var taken := 0
	for line in lines:
		if line.kind == BattleReportBuilder.ROUND_HEAD:
			rounds += 1
		elif line.kind == BattleReport.Kind.DAMAGE_DEALT:
			dealt += int(line.amount)
		elif line.kind == BattleReport.Kind.DAMAGE_TAKEN:
			taken += int(line.amount)
	assert_eq(rounds, 2)
	assert_eq(dealt, 1000)
	assert_eq(taken, 20)
	assert_eq(lines[lines.size() - 1].kind, BattleReport.Kind.WIN)
	assert_string_contains(lines[lines.size() - 1].text, "枯木妖")


func test_battle_report_handles_loss_timeout_and_missing_log() -> void:
	var lost := BattleReportBuilder.build({"win": false, "reason": "defeated", "log": [], "durationSeconds": 3}, "蛇王")
	assert_eq(lost[lost.size() - 1].kind, BattleReport.Kind.LOSE)
	assert_string_contains(lost[0].text, "没有返回战报明细")
	var timeout := BattleReportBuilder.build({"win": false, "reason": "timeout", "log": [], "durationSeconds": 20}, "")
	assert_string_contains(timeout[timeout.size() - 1].text, "首领")


func test_battle_report_renders_into_the_report_control() -> void:
	var report := BattleReport.new()
	add_child_autofree(report)
	var lines := BattleReportBuilder.build(UiMock._fake_battle(UiMock.state()), "枯木妖", 1000, 1200)
	BattleReportBuilder.render(report, lines)
	assert_gt(report.get_parsed_text().length(), 20)
	assert_string_contains(report.get_parsed_text(), "第 1 回合")


func test_item_flags_persist_seen_and_first_run_marks_everything_seen() -> void:
	var path := "user://test_item_flags.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var flags := ItemFlags.at(path)
	flags.adopt_if_first_run(["a", "b"])
	assert_true(flags.seen.has("a"))
	var again := ItemFlags.at(path)
	assert_true(again.seen.has("a"))
	assert_true(again.seen.has("b"))
	again.mark_seen(["c"])
	again.prune(["a", "c"])
	var third := ItemFlags.at(path)
	assert_false(third.seen.has("b"))
	assert_true(third.seen.has("c"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
