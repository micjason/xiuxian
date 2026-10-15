extends Control
## 游戏主界面外壳：背景、顶部栏、底部页签、五个页面（修炼/历练/角色/行囊/功法）、通用弹层、登录层。
## 界面全部由代码搭建，美术来自 ArtLib（res://assets/art/）；main.tscn 里的旧节点保留但隐藏
## （场景测试按名字检查它们），数据和操作由这里统一处理：真实模式走 PlayerApi，演示模式走 UiMock。

const PAGE_CULTIVATE := "cultivate"
const PAGE_ADVENTURE := "adventure"
const PAGE_BAG := "bag"
const PAGE_SKILL := "skill"
const PAGE_CHARACTER := "character"

## 页面 → 背景画。
const PAGE_BACKGROUNDS := {
	PAGE_CULTIVATE: "home",
	PAGE_ADVENTURE: "stage_2",
	PAGE_CHARACTER: "character",
	PAGE_BAG: "bag",
	PAGE_SKILL: "skill",
}

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
var _char_page: CharacterPage
var _bag_page: BagPage
var _skill_page: SkillPage
var _pages: Dictionary = {}
var _mock_tag: Label


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
	_timer.wait_time = 3.0
	_timer.timeout.connect(_refresh_state)
	add_child(_timer)
	if _mock:
		_login.hide()
		_content = UiMock.content()
		_state = UiMock.state()
		_render()
	elif PlayerApi.token().is_empty():
		_login.show()
		_set_status("请先登录。")
	else:
		_login.hide()
		_timer.start()
		_refresh_state()


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
	_home_page.breakthrough_requested.connect(_on_breakthrough)
	_home_page.page_requested.connect(_show_page)
	_home_page.stage_requested.connect(func(slug: String) -> void:
		_select_stage(slug)
		_show_page(PAGE_ADVENTURE))
	_stage_page = StagePage.new()
	_stage_page.stage_selected.connect(_select_stage)
	_stage_page.challenge_requested.connect(func(slug: String) -> void:
		_selected_stage = slug
		_on_challenge())
	_char_page = CharacterPage.new()
	_char_page.popup = _popup
	_char_page.action_requested.connect(_on_page_action)
	_bag_page = BagPage.new()
	_bag_page.popup = _popup
	_bag_page.action_requested.connect(_on_page_action)
	_skill_page = SkillPage.new()
	_skill_page.action_requested.connect(_on_skill)
	_pages = {PAGE_CULTIVATE: _home_page, PAGE_ADVENTURE: _stage_page, PAGE_CHARACTER: _char_page, PAGE_BAG: _bag_page, PAGE_SKILL: _skill_page}
	for page in _pages.values():
		(page as Control).visible = false
		_page_host.add_child(page)
	_top_bar = TopBar.new()
	_top_bar.settings_pressed.connect(func() -> void: CreditsView.show_credits(_popup))
	add_child(_top_bar)
	_tab_bar = TabBarView.new()
	_tab_bar.set_tabs([
		{"id": PAGE_CULTIVATE, "name": "修炼", "icon": "tab_cultivate"},
		{"id": PAGE_ADVENTURE, "name": "历练", "icon": "tab_adventure"},
		{"id": PAGE_CHARACTER, "name": "角色", "icon": "tab_character"},
		{"id": PAGE_BAG, "name": "行囊", "icon": "tab_bag"},
		{"id": PAGE_SKILL, "name": "功法", "icon": "tab_skill"},
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
	_apply_layout()


## 按安全区排布顶部栏、内容区和底部页签。桌面上安全区为 0。
func _apply_layout() -> void:
	var inset := UiSafeArea.current(get_viewport())
	_top_bar.apply_safe_area(inset)
	_tab_bar.apply_safe_area(inset)
	_page_host.offset_left = float(UiTokens.PAGE_MARGIN) + inset.x
	_page_host.offset_right = -(float(UiTokens.PAGE_MARGIN) + inset.z)
	_page_host.offset_top = inset.y + float(TopBar.HEIGHT) + float(UiTokens.SP_1)
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
	_page = page
	for key in _pages:
		(_pages[key] as Control).visible = key == page
	_tab_bar.select(page)
	_backdrop.show_background(str(PAGE_BACKGROUNDS.get(page, "home")))
	if page == PAGE_BAG:
		_bag_page.mark_visible_seen()
		_update_dots()


func _on_logged_in() -> void:
	_login.hide()
	_set_status("")
	_timer.start()
	_refresh_state()


func _refresh_state() -> void:
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
	_state = state
	_render()


func _render() -> void:
	_top_bar.bind(_state)
	_home_page.bind(_state, _content, _realm_name(str((_state.get("breakthrough", {}) as Dictionary).get("nextSlug", ""))), _suggestions(), _busy)
	_flags.adopt_if_first_run(_item_ids())
	_bag_page.bind(_state, _content, _flags)
	_char_page.bind(_state, _content, _flags)
	_stage_render()
	_skill_page.bind(_state, _content)
	_update_dots()


func _stage_render() -> void:
	var stages := _stages_for_current_realm()
	var known := false
	for stage in stages:
		if str(stage.get("slug", "")) == _selected_stage:
			known = true
	if not known:
		_selected_stage = "" if stages.is_empty() else str(stages[0].get("slug", ""))
	_stage_page.bind(_state, _content, stages, _selected_stage)


## 页签红点：能突破、有更强的装备或够强化经验、行囊有新物品、有功法书可学。
func _update_dots() -> void:
	var breakthrough: Dictionary = _state.get("breakthrough", {})
	var gain := float((_state.get("cultivationRate", {}) as Dictionary).get("gainPerTick", 0))
	var can_break := gain > 0.0 and not str(breakthrough.get("nextSlug", "")).is_empty() and float(_state.get("cultivation", 0)) >= float(breakthrough.get("cost", 0))
	_tab_bar.set_dot(PAGE_CULTIVATE, can_break)
	_tab_bar.set_dot(PAGE_CHARACTER, _gear_upgrades() > 0 or _enhanceable_count() > 0)
	var bag := BagModel.from_state(_state, _content, _flags.seen)
	var fresh := false
	var book := false
	for item in bag.items:
		if bool(item.get("equipped", false)):
			continue
		if bool(item.get("is_new", false)) and _page != PAGE_BAG:
			fresh = true
		if str(item.get("kind", "")) == "skill_book":
			book = true
	_tab_bar.set_dot(PAGE_BAG, fresh)
	_tab_bar.set_dot(PAGE_SKILL, book)


func _suggestions() -> Dictionary:
	return {"stage": _suggest_stage(), "upgrades": _gear_upgrades(), "enhanceable": _enhanceable_count()}


## 推荐关卡：战力够的关卡里推荐战力最高的；一个都不够就推荐最低的。
func _suggest_stage() -> Dictionary:
	var power := int(_state.get("power", 0))
	var best := {}
	var lowest := {}
	for stage in _stages_for_current_realm():
		var recommended := int(stage.get("recommendedPower", 0))
		if lowest.is_empty() or recommended < int(lowest.get("recommendedPower", 0)):
			lowest = stage
		if recommended <= power and (best.is_empty() or recommended > int(best.get("recommendedPower", 0))):
			best = stage
	return best if not best.is_empty() else lowest


func _gear_upgrades() -> int:
	var model := BagModel.from_state(_state, _content, {})
	var slots := EquipModel.slots_of(model)
	var count := 0
	for slot in SlotConfig.core():
		if not bool(slot.get("supported", false)):
			continue
		var worn: Dictionary = slots.get(str(slot.id), {})
		for item in EquipModel.candidates_for(model, str(slot.id)):
			if int(item.power) > int(worn.get("power", 0)):
				count += 1
	return count


## 身上的装备里，强化经验够升下一级、或者材料齐了可以突破的有几件。
func _enhanceable_count() -> int:
	var model := BagModel.from_state(_state, _content, {})
	var count := 0
	for item in model.items:
		if not bool(item.get("equipped", false)):
			continue
		if BagModel.can_enhance(item) and model.enhance_exp >= int(item.get("enhance_cost", 0)):
			count += 1
		elif BagModel.can_break(item):
			var pending: Dictionary = (item.get("break_view", {}) as Dictionary).get("pending", {})
			if bool(pending.get("ready", false)):
				count += 1  # 材料齐了，可以突破
	return count


func _item_ids() -> Array:
	var ids: Array = []
	for row in _state.get("items", []):
		if typeof(row) == TYPE_DICTIONARY:
			ids.append(str((row as Dictionary).get("id", "")))
	return ids


func _select_stage(slug: String) -> void:
	_selected_stage = slug
	_stage_render()


func _on_breakthrough() -> void:
	if _busy:
		return
	_busy = true
	_home_page.breakthrough_button().disabled = true
	var result := await _post("/api/v1/me/breakthrough")
	_busy = false
	if int(result.get("code", 0)) != 200:
		_render()
		_toast.say(PlayerApi.error_message(result), false)
		return
	var outcome: Dictionary = result.get("result", {})
	if bool(outcome.get("success", false)):
		_home_page.show_banner("突破成功", true)
	else:
		_home_page.show_banner("突破失败，损失修为 %s" % CultivationFormat.amount(float(outcome.get("lostCultivation", 0))), false)
	_apply_action_state(result)


func _on_challenge() -> void:
	if _busy or _selected_stage.is_empty():
		return
	_busy = true
	_stage_page.set_busy(true)
	var result := await _post("/api/v1/me/stages/%s/challenge" % _selected_stage.uri_encode())
	_busy = false
	_stage_page.set_busy(false)
	if int(result.get("code", 0)) != 200:
		_toast.say(PlayerApi.error_message(result), false)
		_stage_page.show_result({"win": false, "reason": "error", "log": [], "durationSeconds": 0}, "挑战失败", PlayerApi.error_message(result))
		return
	var battle: Dictionary = result.get("battle", {})
	var names: PackedStringArray = []
	for drop in result.get("drops", []):
		if typeof(drop) == TYPE_DICTIONARY:
			var reward := _reward_name(str((drop as Dictionary).get("itemSlug", "")))
			if bool((drop as Dictionary).get("decomposed", false)):
				reward += "（已分解 +%d 强化经验）" % int((drop as Dictionary).get("enhanceExp", 0))
			names.append(reward)
	var loot := "获得：" + ("、".join(names) if not names.is_empty() else "无")
	_apply_action_state(result)
	_stage_page.show_result(battle, _boss_name_of(_selected_stage), loot)


func _on_skill(kind: String, slug: String) -> void:
	if _busy or slug.is_empty():
		return
	_busy = true
	var result: Dictionary
	if kind == "run":
		var slot := "heart" if str(_skill_def(slug).get("role", "")) == "heart" else "art_1"
		result = await _post("/api/v1/me/skills/%s/run" % slug.uri_encode(), {"slot": slot})
	else:
		result = await _post("/api/v1/me/skills/%s/stop" % slug.uri_encode())
	_busy = false
	if int(result.get("code", 0)) != 200:
		_skill_page.show_hint(PlayerApi.error_message(result))
		return
	_skill_page.show_hint("")
	_apply_action_state(result)


func _apply_action_state(result: Dictionary) -> void:
	var state: Variant = result.get("state", {})
	if typeof(state) == TYPE_DICTIONARY:
		_state = state
		_state["code"] = 200
		_render()


## 所有会改变状态的请求都走这里：演示模式用内存里的假数据，正式模式调服务器。
func _post(path: String, body: Dictionary = {}) -> Dictionary:
	if _mock:
		return UiMock.handle(path, body, _state, _content)
	return await PlayerApi.post_action(path, body)


func _boss_name_of(slug: String) -> String:
	var bosses: Array = _stage_def(slug).get("bosses", [])
	if not bosses.is_empty() and typeof(bosses[0]) == TYPE_DICTIONARY:
		return str((bosses[0] as Dictionary).get("name", "首领"))
	return "首领"


## 行囊页、角色页发来的操作。服务器没有批量接口，批量分解是逐件调用后合计。
func _on_page_action(kind: String, ids: Array) -> void:
	if _busy:
		return
	match kind:
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
	elif _page == PAGE_CHARACTER:
		_char_page.show_detail(item_id)


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
	elif _page == PAGE_CHARACTER:
		_char_page.show_detail(item_id)


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
