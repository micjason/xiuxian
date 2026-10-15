extends Control
## 游戏主界面外壳：背景、顶部栏（头像/境界/总战力/修为）、底部四个页签（修炼 / 背包 / 功法 / 洞府）、
## 页面、通用弹层、离线收益弹窗、突破成功弹窗、登录层。
## 修炼页里有「历练」入口（关卡）→ 首领战界面；「突破」按钮 → 境界突破流程界面；它们不占页签。
## 界面全部由代码搭建，美术来自 ArtLib（res://assets/art/）；main.tscn 里的旧节点保留但隐藏
## （场景测试按名字检查它们），数据和操作由这里统一处理：真实模式走 PlayerApi，演示模式走 UiMock。
## 前台心跳：定时拉 /me/state（服务器据此判在线、结算击杀与掉落）；应用切到后台就停，回前台立刻补一次。

const PAGE_CULTIVATE := "cultivate"
const PAGE_ADVENTURE := "adventure"
const PAGE_BATTLE := "battle"
const PAGE_BREAKTHROUGH := "breakthrough"
const PAGE_BAG := "bag"
const PAGE_SKILL := "skill"
const PAGE_CAVE := "cave"

## 页面 → 背景画。
const PAGE_BACKGROUNDS := {
	PAGE_CULTIVATE: "home",
	PAGE_ADVENTURE: "stage_2",
	PAGE_BATTLE: "battle",
	PAGE_BREAKTHROUGH: "breakthrough",
	PAGE_BAG: "bag",
	PAGE_SKILL: "skill",
	PAGE_CAVE: "character",
}
## 不在页签里的页面 → 高亮哪个页签（都算「修炼」）。
const TAB_OF := {PAGE_ADVENTURE: PAGE_CULTIVATE, PAGE_BATTLE: PAGE_CULTIVATE, PAGE_BREAKTHROUGH: PAGE_CULTIVATE}
## 心跳：服务器 onlineGapSeconds（默认 15 秒）内有请求才算在线，所以间隔要比它短。
const HEARTBEAT_MARGIN := 3.0
const HEARTBEAT_DEFAULT := 12.0

## 运行时主题由 MainTheme.make() 导出（scripts/dev/export_theme.gd），改令牌或美术后需重新导出。
const APP_THEME: Theme = preload("res://resources/theme/xiuxian_theme.tres")

var _state: Dictionary = {}
var _content: Dictionary = {}
var _login: PlayerLogin
var _timer: Timer
var _selected_stage := ""
var _busy := false
var _page := PAGE_CULTIVATE
var _mock := false
var _flags: ItemFlags
var _popup: GamePopup
var _backdrop: Backdrop
var _top_bar: TopBar
var _tab_bar: TabBarView
var _toast: Toast
var _page_host: MarginContainer
var _home_page: HomePage
var _stage_page: StagePage
var _battle_page: BattlePage
var _breakthrough_page: BreakthroughPage
var _bag_page: BagPage
var _skill_page: SkillPage
var _cave_page: CavePage
var _offline_popup: OfflinePopup
var _success_popup: BreakthroughSuccess
var _pages: Dictionary = {}
var _mock_tag: Label
var _offline_shown_id := ""
var _heartbeats := 0


func _ready() -> void:
	theme = APP_THEME
	_mock = UiMock.enabled()
	_hide_legacy_nodes()
	_build_shell()
	get_viewport().size_changed.connect(_apply_layout)
	_show_page(PAGE_CULTIVATE)
	_login = PlayerLogin.new()
	_login.logged_in.connect(_on_logged_in)
	add_child(_login)
	_timer = Timer.new()
	_timer.wait_time = HEARTBEAT_DEFAULT
	_timer.timeout.connect(_refresh_state)
	add_child(_timer)
	if _mock:
		var wanted := OS.get_environment("XIUXIAN_MOCK_SCENARIO")
		if not wanted.is_empty():
			ProtoMock.scenario = wanted
		_login.hide()
		_content = ProtoMock.content() if ProtoMock.available() else UiMock.content()
		_state = ProtoMock.state() if ProtoMock.available() else UiMock.state()
		_timer.wait_time = heartbeat_seconds(_state)
		_timer.start()
		_render()
		_maybe_show_offline()
	elif PlayerApi.token().is_empty():
		_login.show()
		_set_status("请先登录。")
	else:
		_login.hide()
		_timer.start()
		_refresh_state()


## 应用切到后台：停心跳（服务器会把这段算离线）；回到前台：马上补一次心跳再恢复定时。
func _notification(what: int) -> void:
	if _timer == null or _mock:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_timer.stop()
	elif what == NOTIFICATION_APPLICATION_RESUMED and not PlayerApi.token().is_empty():
		_timer.start()
		_refresh_state()


## 心跳间隔：服务器的在线判定窗口减去余量，夹在 1..15 秒（读不到就用默认 12 秒）。
static func heartbeat_seconds(state: Dictionary) -> float:
	var wave: Variant = state.get("wave", null)
	if typeof(wave) != TYPE_DICTIONARY or (wave as Dictionary).get("onlineGapSeconds", null) == null:
		return HEARTBEAT_DEFAULT
	return clampf(float((wave as Dictionary).get("onlineGapSeconds", 15)) - HEARTBEAT_MARGIN, 1.0, 15.0)


func heartbeat_count() -> int:
	return _heartbeats


## main.tscn 是旧版界面。节点保留（场景测试检查它们），但全部隐藏，界面由下面的组件接管。
func _hide_legacy_nodes() -> void:
	for child in get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = false
			if child is Control:
				(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_shell() -> void:
	_flags = ItemFlags.at("user://item_flags_mock.json" if _mock else "user://item_flags.json")
	if _mock:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://item_flags_mock.json"))
		_flags = ItemFlags.at("user://item_flags_mock.json")
	_backdrop = Backdrop.new()
	add_child(_backdrop)
	_page_host = MarginContainer.new()
	_page_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_page_host)
	_popup = GamePopup.new()
	_home_page = HomePage.new()
	_home_page.breakthrough_requested.connect(_open_breakthrough)
	_home_page.adventure_requested.connect(func() -> void: _show_page(PAGE_ADVENTURE))
	_home_page.page_requested.connect(_show_page)
	_stage_page = StagePage.new()
	_stage_page.stage_selected.connect(_select_stage)
	_stage_page.challenge_requested.connect(_open_battle)
	_stage_page.idle_stage_requested.connect(_on_idle_stage)
	_stage_page.back_requested.connect(func() -> void: _show_page(PAGE_CULTIVATE))
	_battle_page = BattlePage.new()
	_battle_page.start_blocked.connect(_show_bag_full)
	_battle_page.submit_requested.connect(_on_battle_submit)
	_battle_page.back_requested.connect(func() -> void: _show_page(PAGE_ADVENTURE))
	_battle_page.retry_requested.connect(_open_battle)
	_breakthrough_page = BreakthroughPage.new()
	_breakthrough_page.start_requested.connect(_on_breakthrough)
	_breakthrough_page.goto_stage_requested.connect(func(slug: String) -> void:
		_select_stage(slug)
		_show_page(PAGE_ADVENTURE))
	_bag_page = BagPage.new()
	_bag_page.popup = _popup
	_bag_page.action_requested.connect(_on_page_action)
	_skill_page = SkillPage.new()
	_cave_page = CavePage.new()
	_pages = {PAGE_CULTIVATE: _home_page, PAGE_ADVENTURE: _stage_page, PAGE_BATTLE: _battle_page, PAGE_BREAKTHROUGH: _breakthrough_page, PAGE_BAG: _bag_page, PAGE_SKILL: _skill_page, PAGE_CAVE: _cave_page}
	for page in _pages.values():
		(page as Control).visible = false
		_page_host.add_child(page)
	_top_bar = TopBar.new()
	_top_bar.settings_pressed.connect(func() -> void: CreditsView.show_credits(_popup))
	add_child(_top_bar)
	_tab_bar = TabBarView.new()
	_tab_bar.set_tabs([
		{"id": PAGE_CULTIVATE, "name": "修炼", "icon": "tab_cultivate"},
		{"id": PAGE_BAG, "name": "背包", "icon": "tab_bag"},
		{"id": PAGE_SKILL, "name": "功法", "icon": "tab_skill"},
		{"id": PAGE_CAVE, "name": "洞府", "icon": "tab_cave", "fallback": "ui_gate"},
	] as Array[Dictionary], PAGE_CULTIVATE)
	_tab_bar.page_selected.connect(_show_page)
	add_child(_tab_bar)
	_toast = Toast.new()
	add_child(_toast)
	if _mock:
		_mock_tag = Label.new()
		_mock_tag.text = "演示"
		_mock_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_mock_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_mock_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mock_tag.add_theme_font_size_override("font_size", UiTokens.FS_MICRO)
		_mock_tag.add_theme_color_override("font_color", UiTokens.WARNING)
		_mock_tag.add_theme_stylebox_override("normal", KitStyle.box(Color(0.1, 0.07, 0.02, 0.85), UiTokens.WARNING, 2, UiTokens.R_SM, 6))
		_mock_tag.tooltip_text = "演示数据：不连服务器，操作只在本机内存里生效"
		add_child(_mock_tag)
	add_child(_popup)
	_offline_popup = OfflinePopup.new()
	_offline_popup.acknowledged.connect(_on_offline_ack)
	add_child(_offline_popup)
	_success_popup = BreakthroughSuccess.new()
	_success_popup.closed.connect(func() -> void: _show_page(PAGE_CULTIVATE))
	add_child(_success_popup)
	_apply_layout()


## 按安全区排布顶部栏、内容区和底部页签。桌面上安全区为 0。
func _apply_layout() -> void:
	var inset := UiSafeArea.current(get_viewport())
	_top_bar.apply_safe_area(inset)
	_tab_bar.apply_safe_area(inset)
	_page_host.offset_left = float(UiTokens.PAGE_MARGIN) + inset.x
	_page_host.offset_right = -(float(UiTokens.PAGE_MARGIN) + inset.z)
	_page_host.offset_top = inset.y + _top_bar.content_height() + float(UiTokens.SP_1)
	_page_host.offset_bottom = -(float(TabBarView.HEIGHT) + inset.w + float(UiTokens.SP_2))
	_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_left = float(UiTokens.PAGE_MARGIN) + inset.x
	_toast.offset_right = -(float(UiTokens.PAGE_MARGIN) + inset.z)
	_toast.offset_top = inset.y + float(TopBar.HEIGHT) + float(UiTokens.SP_1)
	_toast.offset_bottom = _toast.offset_top + 110.0
	if _mock_tag != null:
		_mock_tag.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_mock_tag.offset_left = float(UiTokens.PAGE_MARGIN) + inset.x
		_mock_tag.offset_right = _mock_tag.offset_left + 88.0
		_mock_tag.offset_top = inset.y + 2.0
		_mock_tag.offset_bottom = _mock_tag.offset_top + 46.0


func _show_page(page: String) -> void:
	if _page == PAGE_BATTLE and page != PAGE_BATTLE and _battle_page.is_running():
		_toast.say("战斗进行中，打完再离开", false)
		return
	_page = page
	for key in _pages:
		(_pages[key] as Control).visible = key == page
	_tab_bar.select(str(TAB_OF.get(page, page)))
	_backdrop.show_background(str(PAGE_BACKGROUNDS.get(page, "home")))
	if page == PAGE_BAG:
		_bag_page.mark_visible_seen()
		_update_dots()


func _on_logged_in() -> void:
	_login.hide()
	_set_status("")
	_timer.start()
	_refresh_state()


## 心跳：拉 /me/state，服务器按“距上次请求不超过在线窗口”判在线并结算击杀、掉落。
func _refresh_state() -> void:
	if _mock:
		_state = ProtoMock.tick(_state, _content, _timer.wait_time) if ProtoMock.available() else _state
		_heartbeats += 1
		_render(true)
		return
	if PlayerApi.token().is_empty() or _busy:
		return
	if _content.is_empty():
		var content := await PlayerApi.fetch_content()
		if int(content.get("code", 0)) == 200:
			_content = content
		else:
			_set_status("后台还没有发布内容，暂时不能修炼。")
			return
	var state := await PlayerApi.fetch_state()
	if int(state.get("code", 0)) != 200:
		_set_status(PlayerApi.error_message(state))
		return
	_heartbeats += 1
	_state = state
	var wanted := heartbeat_seconds(state)
	if not is_equal_approx(_timer.wait_time, wanted):
		_timer.wait_time = wanted
	_render(true)
	_maybe_show_offline()


## feedback = true 时（心跳 / 行动返回的新结算）把击杀、掉落反馈给修炼页。
func _render(feedback: bool = false) -> void:
	_top_bar.bind(_state)
	_apply_layout()
	var breakthrough: Dictionary = _state.get("breakthrough", {}) if typeof(_state.get("breakthrough", null)) == TYPE_DICTIONARY else {}
	var next_name := _realm_name(BagModel.plain(breakthrough.get("nextSlug", null)))
	_home_page.bind(_state, _content, next_name)
	if feedback:
		var last: Variant = _state.get("lastSettle", null)
		if typeof(last) == TYPE_DICTIONARY:
			var lines := WaveView.feedback(last as Dictionary, _reward_name)
			if not lines.is_empty():
				_home_page.show_feedback(lines)
	_flags.adopt_if_first_run(_item_ids())
	_bag_page.bind(_state, _content, _flags)
	_stage_render()
	_skill_page.bind(_state, _content)
	_breakthrough_page.bind(_state, _content, next_name, _realm_after(BagModel.plain(breakthrough.get("nextSlug", null))))
	_update_dots()


## 下一境界之后再下一个境界的名字（突破页第三个节点）；没有返回空串。
func _realm_after(slug: String) -> String:
	var rows: Array = _content.get("realms", [])
	for index in rows.size():
		if typeof(rows[index]) == TYPE_DICTIONARY and str((rows[index] as Dictionary).get("slug", "")) == slug and index + 1 < rows.size():
			return str((rows[index + 1] as Dictionary).get("displayName", ""))
	return ""


func _stage_render() -> void:
	# 历练页只列有首领的关卡（普通关卡的小怪在修炼页自动刷，用「挂机刷怪地点」选）。
	var stages: Array[Dictionary] = []
	for stage in _stages_for_current_realm():
		if not (stage.get("bosses", []) as Array).is_empty():
			stages.append(stage)
	var known := false
	for stage in stages:
		if str(stage.get("slug", "")) == _selected_stage:
			known = true
	if not known:
		_selected_stage = "" if stages.is_empty() else str(stages[stages.size() - 1].get("slug", ""))
	_stage_page.bind(_state, _content, stages, _selected_stage)


## 页签红点：能突破、背包里有新物品、有更强的装备可换。
func _update_dots() -> void:
	var view := BreakthroughView.build(_state)
	var gain := float((_state.get("cultivationRate", {}) as Dictionary).get("gainPerTick", 0)) if typeof(_state.get("cultivationRate", null)) == TYPE_DICTIONARY else 0.0
	_tab_bar.set_dot(PAGE_CULTIVATE, gain > 0.0 and bool(view.can_start))
	var bag := BagModel.from_state(_state, _content, _flags.seen)
	var fresh := false
	for item in bag.items:
		if not bool(item.get("equipped", false)) and bool(item.get("is_new", false)) and _page != PAGE_BAG:
			fresh = true
	_tab_bar.set_dot(PAGE_BAG, fresh or not EquipModel.best_upgrades(bag).is_empty())
	_tab_bar.set_dot(PAGE_SKILL, false)
	_tab_bar.set_dot(PAGE_CAVE, false)


func _item_ids() -> Array:
	var ids: Array = []
	for row in _state.get("items", []):
		if typeof(row) == TYPE_DICTIONARY:
			ids.append(str((row as Dictionary).get("id", "")))
	return ids


func _select_stage(slug: String) -> void:
	_selected_stage = slug
	_stage_render()


# ───────── 离线收益弹窗 ─────────

## state.offlineReport 有内容（服务器给了且没确认过）就弹窗，同一份只弹一次。
func _maybe_show_offline() -> void:
	var report: Variant = _state.get("offlineReport", null)
	if typeof(report) != TYPE_DICTIONARY or (report as Dictionary).is_empty():
		return
	var id := str((report as Dictionary).get("id", ""))
	if id.is_empty() or id == _offline_shown_id or _offline_popup.visible:
		return
	var bonus_bp := float((_state.get("cultivationRate", {}) as Dictionary).get("bonusBp", 0)) if typeof(_state.get("cultivationRate", null)) == TYPE_DICTIONARY else 0.0
	var view := OfflineView.build(report, SkillView.running_name(_state, _content), bonus_bp / 100.0)
	if view.is_empty():
		return
	_offline_shown_id = id
	_offline_popup.show_report(view)


## 点「领取」：告诉服务器已读（修为早已入账），成功才关；失败留着可再点。
func _on_offline_ack(report_id: String) -> void:
	var result := await _post("/api/v1/me/offline-reports/%s/ack" % report_id.uri_encode())
	if int(result.get("code", 0)) != 200:
		_toast.say(PlayerApi.error_message(result), false)
		_offline_popup.claim_button().disabled = false
		return
	_offline_popup.close_popup()
	if _state.get("offlineReport", null) != null and str((_state.get("offlineReport", {}) as Dictionary).get("id", "")) == report_id:
		_state["offlineReport"] = null


# ───────── 首领战 ─────────

func _open_battle(slug: String) -> void:
	if _busy:
		return
	_selected_stage = slug
	var stage := _stage_def(slug)
	if stage.is_empty():
		return
	var bag := BagModel.from_state(_state, _content, {})
	var gate := bag.challenge_gate(bool(_state.get("autoDecompose", false)))
	_battle_page.open_stage(_state, _content, stage, gate, str(_state.get("realmName", "")))
	_show_page(PAGE_BATTLE)


func _show_bag_full(used: int, capacity: int) -> void:
	BagFullPrompt.show_prompt(_popup, used, capacity, func() -> void: _show_page(PAGE_BAG))


## 战斗画面打完，把大招点击时间随挑战请求上报；胜负和掉落以服务器返回为准。
func _on_battle_submit(slug: String, taps: Array) -> void:
	_busy = true
	var result := await _post("/api/v1/me/stages/%s/challenge" % slug.uri_encode(), {"ultTaps": taps})
	_busy = false
	if int(result.get("code", 0)) != 200:
		var error: Variant = result.get("error", {})
		if typeof(error) == TYPE_DICTIONARY and str((error as Dictionary).get("code", "")) == "BAG_FULL":
			var bag := BagModel.from_state(_state, _content, {})
			_show_bag_full(bag.used_slots(), bag.capacity)
		_battle_page.show_submit_error(PlayerApi.error_message(result))
		return
	_apply_action_state(result)
	_battle_page.show_result(result, _reward_name)


# ───────── 突破 ─────────

func _open_breakthrough() -> void:
	_show_page(PAGE_BREAKTHROUGH)


func _on_breakthrough() -> void:
	if _busy:
		return
	_busy = true
	_breakthrough_page.set_busy(true)
	var before := _state.duplicate(true)
	var unlocks := BreakthroughView.unlocks(before, _content)
	var result := await _post("/api/v1/me/breakthrough")
	_busy = false
	if int(result.get("code", 0)) != 200:
		_render()
		_toast.say(PlayerApi.error_message(result), false)
		return
	var outcome: Dictionary = result.get("result", {})
	_apply_action_state(result)
	if bool(outcome.get("success", false)):
		_success_popup.show_success(BreakthroughView.success_summary(before, _state), unlocks)
	else:
		_toast.say("突破失败，损失修为 %s" % CultivationFormat.amount(float(outcome.get("lostCultivation", 0))), false)


## 选择挂机刷怪关卡（slug 为空 = 自动）。
func _on_idle_stage(slug: String) -> void:
	if _busy:
		return
	_busy = true
	var result := await _post("/api/v1/me/idle-stage", {"stageSlug": null if slug.is_empty() else slug})
	_busy = false
	if int(result.get("code", 0)) != 200:
		_toast.say(PlayerApi.error_message(result), false)
		return
	# 真实服务器直接返回状态本体，演示模式返回 {state}。
	_apply_action_state(result if result.has("state") else {"state": result})


func _apply_action_state(result: Dictionary) -> void:
	var state: Variant = result.get("state", {})
	if typeof(state) == TYPE_DICTIONARY:
		_state = state
		_state["code"] = 200
		_render(true)


## 所有会改变状态的请求都走这里：演示模式用内存里的假数据，正式模式调服务器。
func _post(path: String, body: Dictionary = {}) -> Dictionary:
	if _mock:
		if ProtoMock.available():
			return ProtoMock.handle(path, body, _state, _content)
		return UiMock.handle(path, body, _state, _content)
	return await PlayerApi.post_action(path, body)


## 行囊页、角色页发来的操作。服务器没有批量接口，批量分解是逐件调用后合计。
func _on_page_action(kind: String, ids: Array) -> void:
	if _busy:
		return
	match kind:
		"equip_many":
			await _equip_many(ids)
		"equip":
			await _item_action(str(ids[0]), "equip")
		"unequip":
			await _item_action(str(ids[0]), "unequip")
		"use":
			await _item_action(str(ids[0]), "use")
		"enhance":
			await _enhance(str(ids[0]), false)
		"enhance_max":
			await _enhance(str(ids[0]), true)
		"breakthrough":
			await _breakthrough(str(ids[0]))
		"decompose":
			await _decompose_many(ids)
		"auto_decompose":
			await _on_auto_decompose(bool(ids[0]))


func _item_action(item_id: String, action: String) -> void:
	if item_id.is_empty():
		return
	_busy = true
	var result := await _post("/api/v1/me/items/%s/%s" % [item_id.uri_encode(), action])
	_busy = false
	if int(result.get("code", 0)) != 200:
		_toast.say(PlayerApi.error_message(result), false)
		return
	if action == "use":
		var learned: Dictionary = result.get("learned", {})
		if learned.has("convertedCultivation"):
			_toast.say("功法已圆满，转为修为 %s" % CultivationFormat.amount(float(learned.get("convertedCultivation", 0))))
		else:
			_toast.say("学会了，现在是 %s 层" % str(learned.get("level", "")))
	_apply_action_state(result)


func _enhance(item_id: String, to_max: bool) -> void:
	_busy = true
	var result := await _post("/api/v1/me/items/%s/enhance" % item_id.uri_encode(), {"toMax": to_max})
	_busy = false
	if int(result.get("code", 0)) != 200:
		_toast.say(PlayerApi.error_message(result), false)
		return
	var done: Dictionary = result.get("enhanced", {})
	var message := "强化成功 +%d → +%d，消耗强化经验 %d" % [int(done.get("fromLevel", 0)), int(done.get("toLevel", 0)), int(done.get("spentExp", 0))]
	if done.get("blockedByBreakthrough", null) != null:
		message += "。已到突破节点 +%d，需要先突破" % int(done.get("blockedByBreakthrough", 0))
	_toast.say(message)
	_apply_action_state(result)
	# 回到这件装备的详情，方便连续强化。
	if _page == PAGE_BAG:
		_bag_page.show_detail(item_id)


## 突破：交齐节点材料（服务器从行囊扣），不会失败；材料不够时服务器会写明差多少。
func _breakthrough(item_id: String) -> void:
	_busy = true
	var result := await _post("/api/v1/me/items/%s/breakthrough" % item_id.uri_encode())
	_busy = false
	if int(result.get("code", 0)) != 200:
		_toast.say(PlayerApi.error_message(result), false)
		return
	var done: Dictionary = result.get("broken", {})
	var parts: Array[String] = []
	for material in done.get("materials", []):
		parts.append("%s ×%d" % [BagModel.from_state(_state, _content, {}).item_name(str((material as Dictionary).get("itemSlug", ""))), int((material as Dictionary).get("count", 0))])
	_toast.say("突破成功：+%d 节点已通过，消耗 %s。可以继续强化了" % [int(done.get("level", 0)), "、".join(parts)])
	_apply_action_state(result)
	if _page == PAGE_BAG:
		_bag_page.show_detail(item_id)


func _equip_many(ids: Array) -> void:
	var worn := 0
	for id in ids:
		_busy = true
		var result := await _post("/api/v1/me/items/%s/equip" % str(id).uri_encode())
		_busy = false
		if int(result.get("code", 0)) != 200:
			_toast.say("穿戴到第 %d 件时失败：%s" % [worn + 1, PlayerApi.error_message(result)], false)
			break
		worn += 1
		_apply_action_state(result)
	if worn > 0:
		_toast.say("一键穿戴了 %d 件更强的装备" % worn)


func _decompose_many(ids: Array) -> void:
	var total := 0
	var done := 0
	var skipped := 0
	for id in ids:
		_busy = true
		var result := await _post("/api/v1/me/items/%s/decompose" % str(id).uri_encode())
		_busy = false
		if int(result.get("code", 0)) != 200:
			var error: Variant = result.get("error", {})
			if typeof(error) == TYPE_DICTIONARY and str((error as Dictionary).get("code", "")) == "EQUIPPED_CANNOT_DECOMPOSE":
				skipped += 1
				continue
			_toast.say("分解到第 %d 件时失败：%s" % [done + 1, PlayerApi.error_message(result)], false)
			break
		total += int(result.get("gainedEnhanceExp", 0))
		done += 1
		_apply_action_state(result)
	if done > 0:
		var tail := "（跳过 %d 件已穿戴的装备）" % skipped if skipped > 0 else ""
		_toast.say("分解了 %d 件装备，得到强化经验 %d%s" % [done, total, tail])
	elif skipped > 0:
		_toast.say("已穿戴的装备不能分解，请先脱下", false)


func _on_auto_decompose(enabled: bool) -> void:
	_busy = true
	var result := await _post("/api/v1/me/auto-decompose", {"enabled": enabled})
	_busy = false
	if int(result.get("code", 0)) != 200:
		_toast.say(PlayerApi.error_message(result), false)
		return
	_apply_action_state(result)


func _set_status(message: String) -> void:
	_toast.say(message, false, 6.0)


func _realm_name(slug: String) -> String:
	for row in _content.get("realms", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == slug:
			return str((row as Dictionary).get("displayName", slug))
	return slug


func _current_realm_code() -> int:
	var slug := str(_state.get("realmSlug", ""))
	for row in _content.get("realms", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == slug:
			return int((row as Dictionary).get("sortOrder", -1))
	return -1


func _stages_for_current_realm() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var code := _current_realm_code()
	if code < 0:
		return found
	for row in _content.get("stages", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var stage_code := int((row as Dictionary).get("requiredRealmOrder", -1))
		if stage_code >= 0 and stage_code <= code:
			found.append(row as Dictionary)
	found.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_code := int(left.get("requiredRealmOrder", 0))
		var right_code := int(right.get("requiredRealmOrder", 0))
		if left_code == right_code:
			return str(left.get("displayName", "")) < str(right.get("displayName", ""))
		return left_code < right_code
	)
	return found


func _stage_def(slug: String) -> Dictionary:
	for row in _content.get("stages", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == slug:
			return row
	return {}


func _reward_name(slug: String) -> String:
	var item := _item_def(slug)
	if not item.is_empty():
		var item_name := str(item.get("displayName", ""))
		return item_name if not item_name.is_empty() else "名称缺失"
	var skill := _skill_def(slug)
	if not skill.is_empty():
		var skill_name := str(skill.get("displayName", ""))
		return skill_name if not skill_name.is_empty() else "名称缺失"
	return "名称缺失"


func _item_def(slug: String) -> Dictionary:
	for row in _content.get("items", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == slug:
			return row
	return {}


func _skill_name(slug: String) -> String:
	var definition := _skill_def(slug)
	if definition.is_empty():
		return "功法不存在"
	var name := str(definition.get("displayName", ""))
	return name if not name.is_empty() else "名称缺失"


func _skill_def(slug: String) -> Dictionary:
	for row in _content.get("skills", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == slug:
			return row
	return {}
