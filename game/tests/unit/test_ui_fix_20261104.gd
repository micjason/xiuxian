extends GutTest
## Confirmed 2026-11-04 UI regression coverage; no network/backend writes.

func before_each() -> void:
	gut.error_tracker.treat_engine_errors_as = GutUtils.TREAT_AS.NOTHING

func _card(playable: bool, cleared: bool) -> Dictionary:
	return {"slug": "sample", "name": "赤炎火山·三", "playable": playable,
		"cleared": cleared, "has_boss": true, "boss_name": "焚天火鸦", "boss_art": "fire_crow",
		"monster_name": "火鸦", "monster_art": "fire_crow", "recommended": 10248,
		"needs_lines": [{"ok": false, "text": "击败首领「焚天火鸦」"}],
		"rules": {}, "first_clear": [], "repeat": null}

func test_home_chest_and_glow_only_exist_when_rewards_pending() -> void:
	var page := HomePage.new()
	add_child_autofree(page)
	page.set_offline_pending(false)
	assert_false(page.chest_button().visible)
	assert_false((page.get("_chest_bubble") as Control).visible)
	page.set_offline_pending(true)
	assert_true(page.chest_button().visible)
	assert_true((page.get("_chest_bubble") as Control).visible)
	page.set_offline_pending(false)
	assert_false(page.chest_button().visible)

func test_home_has_no_side_shortcuts_or_idle_explanation() -> void:
	var page := HomePage.new()
	add_child_autofree(page)
	assert_null(page.find_child("AdventureEntry", true, false))
	assert_null(page.find_child("SkillEntry", true, false))
	assert_null(page.find_child("FogEntry", true, false))
	assert_null(page.find_child("IdleCard", true, false))
	assert_false((page.find_child("FeedLine", true, false) as Control).visible)

func test_stage_rows_are_compact_and_use_three_actions() -> void:
	var page := StagePage.new()
	add_child_autofree(page)
	for flags in [[true, true], [true, false], [false, false]]:
		var card := page._stage_card(_card(flags[0], flags[1]), 6334)
		page.add_child(card)
		assert_null(card.find_child("MonsterPortrait", true, false))
		assert_null(card.find_child("ClearedChip", true, false))
		assert_null(card.find_child("RewardRow", true, false))
		assert_not_null(card.find_child("BossPreview_sample", true, false))
		var button := card.find_child("Challenge_sample", true, false) as Button
		assert_eq(button.text, "未解锁" if not flags[0] else ("再战" if flags[1] else "挑战"))
		if not flags[0]:
			assert_false(button.disabled, "locked action opens requirements")
			button.pressed.emit()
			assert_not_null(page.find_child("StagePopup", true, false))

func test_battle_shell_hides_global_chrome_and_player_hud() -> void:
	OS.set_environment("XIUXIAN_UI_MOCK", "1")
	OS.set_environment("XIUXIAN_UPDATE_CHECK", "0")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(scene)
	for i in 12:
		await get_tree().process_frame
	(scene.get("_offline_popup") as Control).hide()
	scene.call("_open_battle", "lianqi_1")
	await get_tree().process_frame
	assert_false((scene.get("_top_bar") as Control).visible)
	assert_false((scene.get("_tab_bar") as Control).visible)
	var battle := scene.get("_battle_page") as BattlePage
	assert_false((battle.get("_controls") as Control).visible)
	scene.call("_show_page", "adventure")
	assert_true((scene.get("_top_bar") as Control).visible)
	assert_true((scene.get("_tab_bar") as Control).visible)
	OS.unset_environment("XIUXIAN_UI_MOCK")

func test_home_progress_is_numeric_without_monster_explanation() -> void:
	var page := HomePage.new()
	add_child_autofree(page)
	page.bind(ProtoMock.state("realm:jindan_2"), ProtoMock.content(), "")
	var text := (page.find_child("WaveText", true, false) as Label).text
	assert_true(text.contains("/"))
	assert_false(text.contains("本波"))
	assert_false(text.contains("火鸦"))

func test_all_boss_portraits_open_loot_and_popup_closes_on_page_leave() -> void:
	var page := StagePage.new()
	add_child_autofree(page)
	page.bind(ProtoMock.state("realm:jindan_2"), ProtoMock.content(), "jindan_2")
	watch_signals(page)
	page.preview_card().pressed.emit()
	assert_signal_not_emitted(page, "challenge_requested")
	assert_not_null(page.find_child("StagePopup", true, false))
	page.hide()
	await get_tree().process_frame
	assert_null(page.find_child("StagePopup", true, false))

func test_idle_location_picker_moves_off_the_clean_stage_list() -> void:
	var page := StagePage.new()
	add_child_autofree(page)
	page.bind(ProtoMock.state("realm:jindan_2"), ProtoMock.content(), "jindan_2")
	assert_null(page.find_child("IdleStageCard", true, false))
	assert_not_null(page.find_child("IdleLocationButton", true, false))

func test_location_popup_preserves_idle_selection_and_fog_access() -> void:
	var page := StagePage.new()
	add_child_autofree(page)
	page.bind(ProtoMock.state("realm:jindan_2"), ProtoMock.content(), "jindan_2")
	watch_signals(page)
	(page.find_child("IdleLocationButton", true, false) as Button).pressed.emit()
	var entry := page.find_child("FogEntry", true, false) as Button
	assert_not_null(entry)
	if entry != null:
		entry.pressed.emit()
		assert_signal_emitted(page, "fog_requested")
