extends GutTest

func test_uses_server_hp_and_never_recomputes_damage() -> void:
	var playback_script: Script = load("res://scripts/model/battle_timeline.gd")
	assert_not_null(playback_script)
	if playback_script == null:
		return
	var f: BossFight = playback_script.new()
	f.call("load_session", {"battle": {"win": true, "reason": "win", "durationSeconds": 3.0, "log": [{"t": 1.0, "side": "player", "damage": 99999, "kind": "skill", "playerHpAfter": 90.0, "bossHpAfter": 42.0, "targetHpAfter": 42.0}, {"t": 3.0, "side": "player", "damage": 42, "bossHpAfter": 0.0, "targetHpAfter": 0.0}]}, "playback": {"player": {"hp": 100}, "monster": {"hp": 200}, "timeLimitSeconds": 45}})
	f.advance_to(1.0)
	assert_eq(f.boss_hp, 42.0)
	assert_eq(f.player_hp, 90.0)
	assert_eq(f.take_events().size(), 1)
	assert_false(f.finished)
	f.advance_to(3.0)
	assert_true(f.finished)
	assert_true(f.win)
	assert_eq(f.take_events().size(), 1)
	f.advance_to(100.0)
	assert_eq(f.take_events().size(), 0)

func test_timeout_waits_for_server_duration_not_last_event() -> void:
	var playback_script: Script = load("res://scripts/model/battle_timeline.gd")
	if playback_script == null:
		assert_true(false, "missing timeline player")
		return
	var f: BossFight = playback_script.new()
	f.call("load_session", {"battle": {"win": false, "reason": "timeout", "durationSeconds": 45, "log": []}, "playback": {"player": {"hp": 100}, "monster": {"hp": 200}, "timeLimitSeconds": 45}})
	f.advance_to(44.0)
	assert_false(f.finished)
	f.advance_to(45.0)
	assert_true(f.finished)
	assert_eq(f.reason, "timeout")

func test_shared_page_keeps_speed_three_and_hides_stat_panel() -> void:
	var script: Script = load("res://scripts/ui/pages/timeline_battle_page.gd")
	var page: Control = script.new()
	add_child_autofree(page)
	await get_tree().process_frame
	var session: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/combat_timeline.json"))
	page.call("open_session", session, {}, {}, false)
	page.call("_set_speed", 3.0)
	assert_eq(page.get("speed"), 3.0)
	assert_false((page.get("_controls") as Control).visible)
	assert_true((page.get("_skip") as Button).visible)
	page.call("_cycle_speed")
	assert_eq(page.get("speed"), 1.0)
	page.call("abort")

func test_report_describes_dodge_critical_skill_and_retreat() -> void:
	assert_true(str(BattleReportBuilder.live_line({"side": "player", "damage": 0, "dodged": true}, "敌人").text).contains("闪避"))
	assert_true(str(BattleReportBuilder.live_line({"side": "player", "kind": "skill", "damage": 20, "name": "护体诀", "critical": true}, "敌人").text).contains("护体诀"))
	assert_true(str(BattleReportBuilder.live_line({"side": "player", "damage": 20, "critical": true}, "敌人").text).contains("暴击"))
	var view := BattleResultView.build({"battle": {"win": false, "reason": "retreat", "durationSeconds": 1, "log": []}}, "敌人", func(s: String) -> String: return s)
	assert_true(str(view.reason).contains("撤退"))

func test_stage_and_fog_share_one_standalone_page() -> void:
	OS.set_environment("XIUXIAN_UI_MOCK", "1")
	OS.set_environment("XIUXIAN_UPDATE_CHECK", "0")
	var screen: Control = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	screen.call("_open_battle", "lianqi_3")
	var page: TimelineBattlePage = screen.get("_battle_page")
	assert_false((screen.get("_top_bar") as Control).visible)
	assert_false((screen.get("_tab_bar") as Control).visible)
	var session: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/combat_timeline.json"))
	screen.call("_on_fog_battle", session)
	assert_eq(screen.get("_battle_page"), page)
	assert_eq(page.source, "fog")
	assert_true(page.fight is BattleTimeline)
	assert_false((page.get("_controls") as Control).visible)
	page.abort()

func test_session_uses_target_realm_and_power_even_without_opening_stage_first() -> void:
	var page := TimelineBattlePage.new()
	add_child_autofree(page)
	await get_tree().process_frame
	var session: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/combat_timeline.json"))
	session["source"] = "stage"
	session["target"] = {"stageSlug": "real_stage"}
	var content := {"realms": [{"sortOrder": 7, "displayName": "炼气七层"}], "stages": [{"slug": "real_stage", "displayName": "青竹林·七", "requiredRealmOrder": 7, "recommendedPower": 12345}]}
	page.open_session(session, {}, content, false)
	assert_eq((page.get("_boss_realm") as Label).text, "炼气七层")
	assert_true((page.get("_boss_power") as Label).text.contains("12,345"))
	assert_eq((page.get("_title") as Label).text, "青竹林·七")
	page.abort()

func test_status_labels_only_show_remaining_seconds_not_effect_magnitude() -> void:
	var page := TimelineBattlePage.new()
	add_child_autofree(page)
	await get_tree().process_frame
	var session: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/combat_timeline.json"))
	page.open_session(session, {}, {}, false)
	page.set("_shown_statuses", [{"kind": "attack_up", "side": "player", "valueBp": 2500, "expiresAt": 3.0}])
	page.call("_refresh_statuses")
	assert_eq((page.get("_statuses") as Label).text, "↑攻 3s")
	page.fight.t = 3.0
	page.call("_refresh_statuses")
	assert_eq((page.get("_statuses") as Label).text, "")
	page.abort()
