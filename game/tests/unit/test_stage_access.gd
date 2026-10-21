extends GutTest
## 第三批：关卡解锁链（击败上一关首领 + 境界，服务器 stageAccess）、历练页按钮状态、章节背景 / 首领特效、
## 立绘按 artKey 找、自动挑战提示。数据来自真实服务器生成的演示数据集（resources/mock/prototype_dataset.json）。


func before_each() -> void:
	gut.error_tracker.treat_engine_errors_as = GutUtils.TREAT_AS.NOTHING


func _boot(scenario: String) -> Node:
	OS.set_environment("XIUXIAN_UI_MOCK", "1")
	OS.set_environment("XIUXIAN_MOCK_SCENARIO", scenario)
	var holder := SubViewport.new()
	holder.size = Vector2i(1080, 2340)
	holder.disable_3d = true
	add_child_autofree(holder)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	holder.add_child(scene)
	for i in 4:
		await get_tree().process_frame
	OS.unset_environment("XIUXIAN_UI_MOCK")
	OS.unset_environment("XIUXIAN_MOCK_SCENARIO")
	(scene.get("_offline_popup") as Control).hide()
	return scene


func _card(chapters: Array[Dictionary], slug: String) -> Dictionary:
	for chapter in chapters:
		for card in chapter.cards:
			if str(card.slug) == slug:
				return card
	return {}


func test_chapters_follow_chapter_then_stage_order() -> void:
	var content := ProtoMock.content()
	var chapters := StageAccessView.chapters(content, ProtoMock.state("fresh"))
	var names: Array = chapters.map(func(c: Dictionary) -> String: return str(c.slug))
	assert_eq(names, ["heifeng", "youming", "chiyan"])
	var order: Array = []
	for chapter in chapters:
		for card in chapter.cards:
			order.append(str(card.slug))
	assert_eq(order, ["lianqi_1", "lianqi_2", "lianqi_3", "zhuji_1", "zhuji_2", "zhuji_3", "jindan_1", "jindan_2", "jindan_3"])
	assert_eq(str(_card(chapters, "lianqi_3").tier), "chief")
	assert_eq(str(_card(chapters, "lianqi_1").tier), "elite")
	assert_eq(str(_card(chapters, "lianqi_1").boss_art), "wolf", "精英立绘 = 后台 artKey")
	assert_false(bool(chapters[1].unlocked), "新玩家幽冥古道锁着")
	assert_true(str(chapters[1].lock_text).contains("黑风熊王"), str(chapters[1].lock_text))


## 解锁链：新号只能打炼气一层；打赢一层精英后，二层「击败上一关首领」满足，但境界不够还是不能打；
## 境界到了（炼气二层的服务器快照）才能打。打赢章末首领黑风熊王解锁幽冥古道第一关的首领条件。
func test_unlock_chain_needs_previous_boss_and_realm() -> void:
	var content := ProtoMock.content()
	var state := ProtoMock.state("fresh")
	var chapters := StageAccessView.chapters(content, state)
	assert_true(bool(_card(chapters, "lianqi_1").playable))
	assert_false(bool(_card(chapters, "lianqi_2").playable))
	assert_eq(StageAccessView.button(_card(chapters, "lianqi_1"), state).text, "挑 战")
	assert_eq(StageAccessView.button(_card(chapters, "lianqi_2"), state).text, "未解锁")
	var lines: Array = _card(chapters, "lianqi_2").needs_lines
	assert_eq(lines.size(), 2)
	assert_false(bool(lines[0].ok))
	ProtoMock.mark_cleared(state, "lianqi_1")
	chapters = StageAccessView.chapters(content, state)
	assert_true(bool(_card(chapters, "lianqi_1").cleared))
	lines = _card(chapters, "lianqi_2").needs_lines
	assert_true(bool(lines[0].ok), "首领条件满足")
	assert_false(bool(lines[1].ok), "境界还不够")
	assert_false(bool(_card(chapters, "lianqi_2").playable), "境界不够还是不能打")
	assert_eq(StageAccessView.button(_card(chapters, "lianqi_1"), state).text, "再 战", "打过的精英可以再战")
	# 炼气三层的真实快照：一、二层打过，三层（章末首领）能打；打赢后幽冥古道第一关只差境界
	var gate := ProtoMock.state("realm:lianqi_3")
	chapters = StageAccessView.chapters(content, gate)
	assert_true(bool(_card(chapters, "lianqi_3").playable))
	assert_false(bool(_card(chapters, "lianqi_3").cleared))
	assert_false(bool(_card(chapters, "zhuji_1").unlocked))
	ProtoMock.mark_cleared(gate, "lianqi_3")
	chapters = StageAccessView.chapters(content, gate)
	assert_true(bool(_card(chapters, "zhuji_1").unlocked), "击败黑风熊王 → 幽冥古道第一关首领条件满足")
	assert_false(bool(_card(chapters, "zhuji_1").playable), "还要筑基一层")


## 挑战接口（演示）打赢后 stageAccess 跟着变：选中的下一关按钮从「未解锁」变成能点（境界够的话）。
func test_mock_challenge_win_updates_stage_access() -> void:
	var content := ProtoMock.content()
	var state := ProtoMock.state("realm:lianqi_3")
	for row in state.stageAccess:
		if str(row.slug) == "lianqi_2":
			row["cleared"] = false
	var chapters := StageAccessView.chapters(content, state)
	assert_false(bool(_card(chapters, "lianqi_2").cleared))
	state["power"] = 999999
	state["attack"] = 99999.0
	state["hp"] = 999999.0
	var result := ProtoMock.handle("/api/v1/me/stages/lianqi_2/challenge", {}, state, content)
	assert_eq(int(result.get("code", 0)), 200)
	if bool((result.battle as Dictionary).win):
		chapters = StageAccessView.chapters(content, state)
		assert_true(bool(_card(chapters, "lianqi_2").cleared), "打赢 → 首通")


func test_button_states_follow_boss_rules_and_daily_limit() -> void:
	var card := {"slug": "s", "has_boss": true, "playable": true, "cleared": true, "rules": {"allowRepeat": true, "repeatRewards": true, "dailyRewardLimit": 5}}
	var state := {"bossDaily": [{"stageSlug": "s", "used": 2, "limit": 5}]}
	var b := StageAccessView.button(card, state)
	assert_eq(b.text, "再 战")
	assert_eq(b.sub, "今日 3/5")
	assert_true(bool(b.enabled))
	state.bossDaily[0]["used"] = 5
	b = StageAccessView.button(card, state)
	assert_false(bool(b.enabled), "次数用完")
	assert_eq(b.sub, "明日再来")
	card.rules["repeatRewards"] = false
	b = StageAccessView.button(card, state)
	assert_eq(b.sub, "无奖励")
	assert_eq(b.kind, "m")
	assert_true(StageAccessView.daily(card, state).is_empty(), "不发重复奖励就不显示次数")
	card.rules["allowRepeat"] = false
	assert_eq(StageAccessView.button(card, state).text, "已击败")
	card["cleared"] = false
	assert_eq(StageAccessView.button(card, state).text, "挑 战")
	card["playable"] = false
	assert_false(bool(StageAccessView.button(card, state).enabled))


func test_auto_challenge_text() -> void:
	assert_eq(StageAccessView.auto_challenge_text(null), "")
	assert_eq(StageAccessView.auto_challenge_text({"kills": 3}), "")
	var win := StageAccessView.auto_challenge_text({"autoChallenge": {"stageSlug": "lianqi_1", "bossName": "精英·青鬃狼", "tier": "elite", "win": true, "drops": [{"itemSlug": "x"}, {"itemSlug": "y", "dropped": true}]}})
	assert_eq(win, "自动挑战精英「精英·青鬃狼」胜利，获得 1 件物品")
	var lose := StageAccessView.auto_challenge_text({"autoChallenge": {"bossName": "黑风熊王", "tier": "chief", "win": false, "drops": []}})
	assert_eq(lose, "自动挑战章末首领「黑风熊王」失败，稍后再试")


func test_art_key_first_then_name() -> void:
	assert_eq(ArtLib.monster_sprite_for({"artKey": "fox", "name": "精英·青鬃狼"}), "mon_fox", "artKey 优先，不按名字")
	assert_eq(ArtLib.monster_sprite_for({"artKey": null, "name": "精英·青鬃狼"}), "mon_wolf", "没 artKey 按名字")
	assert_eq(ArtLib.monster_sprite_for({"artKey": "no_such_art", "name": "黑风熊王"}), "mon_bear", "没这张图退回名字")
	assert_eq(ArtLib.chapter_bg_name("chiyan"), "bg_chiyan_1080x960")
	assert_eq(ArtLib.chapter_bg_name("nope"), "")
	assert_eq(ArtLib.chapter_bg_name(""), "")


func test_boss_fx_comes_from_the_stage_chapter() -> void:
	var content := ProtoMock.content()
	var stages := {}
	for row in content.stages:
		stages[str(row.slug)] = row
	assert_eq(BattlePage.boss_fx_of(content, stages["jindan_1"]), "chiyan")
	assert_eq(BattlePage.boss_fx_of(content, stages["lianqi_1"]), "default")
	assert_eq(BattlePage.boss_fx_of(content, {}), "default")


## 赤炎火山的首领战：章节背景 + 赤炎特效；历练页背景跟着挂机所在章节。
func test_chiyan_battle_uses_chapter_bg_and_boss_fx() -> void:
	var scene := await _boot("top")
	scene.call("_show_page", "adventure")
	await get_tree().process_frame
	var backdrop: Node = scene.get("_backdrop")
	assert_eq(str(backdrop.call("current_background")), "bg_chiyan_1080x960", "挂机在赤炎火山 → 赤炎背景")
	scene.call("_open_battle", "jindan_3")
	await get_tree().process_frame
	assert_eq(str(backdrop.call("current_background")), "bg_chiyan_1080x960")
	var battle := scene.get("_battle_page") as BattlePage
	var fx: Node = battle.get("_fx")
	assert_eq(str((fx.get("boss") as Node).get("fx_variant")), "chiyan")
	assert_eq(int(fx.get("tier")), 2, "赤焰蛟是章末首领")


func test_heifeng_elite_battle_uses_default_fx() -> void:
	var scene := await _boot("gate")
	scene.call("_open_battle", "lianqi_1")
	await get_tree().process_frame
	var battle := scene.get("_battle_page") as BattlePage
	var fx: Node = battle.get("_fx")
	assert_eq(str((fx.get("boss") as Node).get("fx_variant")), "default")
	assert_eq(int(fx.get("tier")), 1, "精英")
	assert_eq(str((scene.get("_backdrop") as Node).call("current_background")), "bg_heifeng_1080x960")


func test_auto_challenge_result_toasts_once() -> void:
	var scene := await _boot("gate")
	var state: Dictionary = scene.get("_state")
	var last: Dictionary = state.get("lastSettle", {})
	last["autoChallenge"] = {"stageSlug": "lianqi_3", "bossName": "黑风熊王", "tier": "chief", "win": true, "durationSeconds": 20, "drops": [], "reward": {}}
	state["lastSettle"] = last
	scene.call("_render", true)
	var toast := scene.get("_toast") as Toast
	assert_eq(toast.text(), "自动挑战章末首领「黑风熊王」胜利")
	assert_false((state.lastSettle as Dictionary).has("autoChallenge"), "提示过就拿掉，重画不再弹")


func test_tab_switch_shows_that_chapter_and_selects_its_stage() -> void:
	var scene := await _boot("top")
	scene.call("_show_page", "adventure")
	await get_tree().process_frame
	var page := scene.get("_stage_page") as StagePage
	assert_eq(page.current_tab(), "chiyan")
	page.select_tab("heifeng")
	await get_tree().process_frame
	assert_eq(page.current_tab(), "heifeng")
	assert_not_null(page.find_child("Stage_lianqi_1", true, false))
	assert_null(page.find_child("Stage_jindan_1", true, false), "只显示这一章的关卡")
	assert_true(page.selected.begins_with("lianqi_"), page.selected)
