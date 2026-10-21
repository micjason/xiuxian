extends GutTest
## v10 回归：标签栏贴底（各种窗口比例）、桌面不读系统安全区、历练页空状态不再和“挂机刷怪地点”打架。
## 无头模式字体缓存的引擎错误不算失败。

const PAGES := ["cultivate", "adventure", "bag", "skill", "cave"]
## 宽度固定 1080，高度随屏幕比例变（540×960 / 540×1170 / 1080×1920 / 1080×2340 / 1080×2520 的画布大小）。
const CANVAS_SIZES := [Vector2i(1080, 1920), Vector2i(1080, 2340), Vector2i(1080, 2520), Vector2i(1125, 2436)]


func before_each() -> void:
	gut.error_tracker.treat_engine_errors_as = GutUtils.TREAT_AS.NOTHING


## 在指定大小的 SubViewport 里启动主界面（演示数据），相当于窗口被拉成这个画布大小。
func _boot_in(canvas: Vector2i, scenario: String = "ready") -> Node:
	OS.set_environment("XIUXIAN_UI_MOCK", "1")
	OS.set_environment("XIUXIAN_MOCK_SCENARIO", scenario)
	var holder := SubViewport.new()
	holder.size = canvas
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


func _assert_dock_layout(scene: Node, canvas: Vector2i, inset_bottom: float, label: String) -> void:
	var tab := scene.get("_tab_bar") as Control
	var host := scene.get("_page_host") as Control
	for page in PAGES:
		scene.call("_show_page", page)
		await get_tree().process_frame
		await get_tree().process_frame
		var tab_rect := tab.get_global_rect()
		assert_almost_eq(tab_rect.end.y, float(canvas.y), 0.6, "%s %s：标签栏下沿贴视口底" % [label, page])
		assert_almost_eq(tab_rect.size.x, float(canvas.x), 0.6, "%s %s：标签栏通宽" % [label, page])
		assert_almost_eq(tab_rect.size.y, float(TabBarView.HEIGHT) + maxf(inset_bottom, float(TabBarView.SAFE_FILL_MIN)), 0.6, "%s %s：高度 = 标签栏 + 同色填充（≥48，手势条更高时取手势条）" % [label, page])
		var host_rect := host.get_global_rect()
		assert_lte(host_rect.end.y, tab_rect.position.y, "%s %s：内容区在标签栏上面，不被盖住" % [label, page])
		assert_gt(host_rect.size.y, float(canvas.y) * 0.55, "%s %s：内容区拿到大部分高度" % [label, page])
		var visible_page := scene.get("_pages")[page] as Control
		assert_lte(visible_page.get_global_rect().end.y, tab_rect.position.y + 0.6, "%s %s：页面本体不越过标签栏" % [label, page])


func test_tab_bar_is_flush_to_the_bottom_at_every_canvas_ratio() -> void:
	for canvas in CANVAS_SIZES:
		var scene := await _boot_in(canvas)
		await _assert_dock_layout(scene, canvas, 0.0, "%dx%d" % [canvas.x, canvas.y])


func test_tab_bar_sits_above_the_gesture_bar_but_its_background_reaches_the_bottom() -> void:
	OS.set_environment("XIUXIAN_SAFE_AREA", "0,90,0,48")
	var scene := await _boot_in(Vector2i(1080, 2340))
	await _assert_dock_layout(scene, Vector2i(1080, 2340), 48.0, "刘海模拟")
	OS.unset_environment("XIUXIAN_SAFE_AREA")


func test_desktop_never_reads_the_os_safe_area() -> void:
	# 桌面（含 Mac 编辑器）的“安全区”是整块屏幕扣掉菜单栏/Dock，和游戏窗口无关，读了会在窗口底部多出空白。
	if UiSafeArea.platform_has_safe_area():
		pending("手机平台才读系统安全区")
		return
	assert_eq(UiSafeArea.current(get_viewport()), Vector4.ZERO)


func test_mac_style_usable_rect_would_have_made_a_gap_but_is_ignored_on_desktop() -> void:
	# Mac 1512×982（含刘海屏）：菜单栏 76 像素、Dock 140 像素，系统的“可用区域”是 y=76..842。
	var screen := Vector2i(3024, 1964)
	var usable := Rect2i(0, 76, 3024, 1964 - 76 - 140)
	var as_if_phone := UiSafeArea.compute(usable, screen, 1.0)
	assert_eq(as_if_phone.w, 140.0, "当年的 bug：这个 140 会变成标签栏下面的空白")
	assert_eq(as_if_phone.y, 76.0)
	assert_eq(UiSafeArea.resolve(false, usable, screen, 1.0), Vector4.ZERO, "桌面一律不用")
	assert_eq(UiSafeArea.resolve(true, usable, screen, 1.0), as_if_phone, "手机照常使用")


func test_layout_has_no_hardcoded_canvas_height() -> void:
	var holder := SubViewport.new()
	holder.size = Vector2i(1080, 2520)
	add_child_autofree(holder)
	var login := PlayerLogin.new()
	holder.add_child(login)
	await get_tree().process_frame
	assert_eq(UiTokens.BASE_SIZE, Vector2(1080, 2340))
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_width")), 1080)
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_height")), 2340)
	assert_eq(str(ProjectSettings.get_setting("display/window/stretch/mode")), "canvas_items")
	assert_eq(str(ProjectSettings.get_setting("display/window/stretch/aspect")), "keep_width")


# ───────── 历练页：没有首领可打 ─────────

func _state_for(realm_slug: String, content: Dictionary) -> Dictionary:
	var state := ProtoMock.state("fresh")
	state.merge(ProtoMock.realm_snapshot(realm_slug), true)
	state["wave"] = ProtoMock._wave(content, state, realm_slug)
	return state


func _texts(root: Node, out: Array[String] = []) -> Array[String]:
	if root is Label:
		out.append((root as Label).text)
	elif root is Button:
		out.append((root as Button).text)
	for child in root.get_children():
		_texts(child, out)
	return out


## 第三批：历练页按章节分页签、竖排关卡卡，能不能打全看服务器 stageAccess（每个境界的演示快照都来自真实服务器）。
func test_stage_page_cards_follow_server_stage_access_in_every_realm() -> void:
	var scene := await _boot_in(Vector2i(1080, 2340), "gate")
	var content: Dictionary = scene.get("_content")
	var stage_page := scene.get("_stage_page") as StagePage
	for row in content.get("realms", []):
		var slug := str((row as Dictionary).get("slug", ""))
		var state := _state_for(slug, content)
		scene.set("_state", state)
		scene.call("_render")
		await get_tree().process_frame
		var access := StageAccessView.access_map(state)
		assert_false(access.is_empty(), "%s：服务器给了 stageAccess" % slug)
		var tabs := stage_page.find_child("ChapterTabs", true, false)
		assert_not_null(tabs, "%s：有章节页签" % slug)
		assert_eq(tabs.get_child_count(), (content.get("chapters", []) as Array).size(), "%s：每章一个页签" % slug)
		var list := stage_page.find_child("StageCards", true, false)
		assert_not_null(list, "%s：有竖排关卡卡" % slug)
		for card in list.get_children():
			var stage_slug := str(card.name).trim_prefix("Stage_")
			var acc: Dictionary = access.get(stage_slug, {})
			var button := stage_page.challenge_button_for(stage_slug)
			assert_not_null(button, "%s/%s：每张卡都有按钮" % [slug, stage_slug])
			if not bool(acc.get("playable", false)):
				assert_true(button.disabled, "%s/%s：没解锁的不能打" % [slug, stage_slug])
				assert_eq(button.text, "未解锁")
		var chosen := stage_page.challenge_button()
		assert_not_null(chosen, "%s：默认选中一个关卡" % slug)
		assert_false(chosen.disabled, "%s：默认选中的关卡能打（%s）" % [slug, stage_page.selected])
		assert_true(bool((access.get(stage_page.selected, {}) as Dictionary).get("playable", false)), "%s：默认选中能打的关卡" % slug)


## 炼气二层：炼气一层的精英打过了（再战），炼气二层能打（挑战），炼气三层章末首领黑风熊王锁着，写明两个条件；
## 幽冥古道章节锁着，页签上写「击败章末首领「黑风熊王」」。
func test_lianqi_2_points_to_lianqi_3_and_the_bear_king() -> void:
	var scene := await _boot_in(Vector2i(1080, 2340), "gate")
	var content: Dictionary = scene.get("_content")
	scene.set("_state", _state_for("lianqi_2", content))
	scene.set("_selected_stage", "")
	scene.set("_selected_realm", "")
	scene.call("_render")
	await get_tree().process_frame
	var stage_page := scene.get("_stage_page") as StagePage
	assert_eq(stage_page.current_tab(), "heifeng")
	assert_eq(stage_page.selected, "lianqi_2", "默认选中能打没打过的关卡")
	assert_eq(stage_page.challenge_button_for("lianqi_1").text, "再 战")
	assert_eq(stage_page.challenge_button_for("lianqi_2").text, "挑 战")
	assert_false(stage_page.challenge_button_for("lianqi_2").disabled)
	var locked := stage_page.challenge_button_for("lianqi_3")
	assert_eq(locked.text, "未解锁")
	assert_true(locked.disabled)
	var card := stage_page.find_child("Stage_lianqi_3", true, false)
	var text := "\n".join(_texts(card))
	assert_true(text.contains("黑风熊王"), text)
	assert_true(text.contains("首领"), text)
	assert_true(text.contains("击败首领「精英·赤眼狐妖」"), text)
	assert_true(text.contains("达到炼气三层"), text)
	var youming := stage_page.find_child("ChapterTab_youming", true, false) as Button
	assert_true(youming.disabled, "幽冥古道还没解锁")
	assert_true("\n".join(_texts(youming)).contains("黑风熊王"), "页签写明解锁条件")
	assert_not_null(stage_page.find_child("IdleStageCard", true, false), "挂机刷怪地点仍然在")


## 演示数据的修为不能超过本境界突破所需（曾出现「3,300 / 300」）。最高境界没有 cost，不检查。
func test_mock_scenes_cultivation_never_exceeds_requirement() -> void:
	var scenes: Array = ["ready", "fresh", "full", "gate", "top"]
	for slug in (ProtoMock._dataset().get("realms", {}) as Dictionary).keys():
		scenes.append("realm:%s" % slug)
	for scene in scenes:
		var state := ProtoMock.state(scene)
		var cost := float((state.get("breakthrough", {}) as Dictionary).get("cost", 0))
		var exp_now := float(state.get("cultivation", 0))
		assert_true(exp_now >= 0.0, "%s 修为不能为负" % scene)
		if cost > 0.0:
			assert_true(exp_now <= cost, "%s 修为 %s 超过所需 %s" % [scene, exp_now, cost])
	var lq2 := ProtoMock.state("realm:lianqi_2")
	var ratio := float(lq2.cultivation) / float(lq2.breakthrough.cost)
	assert_true(ratio >= 0.6 and ratio <= 0.9, "realm 场景取 60%%~90%%，实际 %s" % ratio)
