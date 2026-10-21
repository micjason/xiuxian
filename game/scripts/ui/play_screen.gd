extends Control
## 游戏主界面外壳（Q 版）：背景、顶部栏（头像/境界/战力/货币/修为）、底部五格（修炼 / 历练 /【突破】/ 功法 / 背包）、
## 页面、通用弹层、离线收益弹窗、突破成功弹窗、登录层。
## 底栏正中的「突破」大圆钮打开境界突破弹窗（居中弹出，盖在当前页上）；修炼页右侧「洞府」入口进洞府页；
## 历练页「挑战」→ 首领战界面。洞府 / 首领战不占页签，分别高亮「修炼」「历练」。
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
	PAGE_BAG: "",
	PAGE_SKILL: "",
	PAGE_CAVE: "character",
}
## 不在页签里的页面 → 高亮哪个页签（都算「修炼」）。
const TAB_OF := {PAGE_BATTLE: PAGE_ADVENTURE, PAGE_CAVE: PAGE_CULTIVATE}
## 顶栏第二行（修为条）只在这些页显示（设计稿：修炼、功法）。
const PAGES_WITH_CULTIVATION := [PAGE_CULTIVATE, PAGE_SKILL]
## 心跳：服务器 onlineGapSeconds（默认 15 秒）内有请求才算在线，所以间隔要比它短。
const HEARTBEAT_MARGIN := 3.0
const HEARTBEAT_DEFAULT := 12.0

## 运行时主题由 MainTheme.make() 导出（scripts/dev/export_theme.gd），改令牌或美术后需重新导出。
const APP_THEME: Theme = preload("res://resources/theme/xiuxian_theme.tres")
const ITEM_POPUP_SCENE: PackedScene = preload("res://scenes/ui/item_detail_popup.tscn")

## 绘制层级：动画场景里的部件自带 z_index（主角最高 20、飘字 50、掉落 40），会盖过后面添加的普通控件，
## 所以外壳各层显式抬高：顶 / 底栏 < 特效层 < 突破弹窗 < 登录页 < 其它弹窗 < 提示条。点击顺序仍按节点顺序（和层级一致）。
const Z_BARS := 30
const Z_FX := 60
const Z_BREAK := 100
const Z_LOGIN := 150  # 登录页盖住整个主界面（顶/底栏、主角），更新弹窗和提示条仍在它上面
const Z_POPUP := 200
const Z_TOAST := 300

var _state: Dictionary = {}
var _content: Dictionary = {}
var _login: PlayerLogin
var _timer: Timer
var _selected_stage := ""
var _selected_realm := ""
var _busy := false
var _page := PAGE_CULTIVATE
var _mock := false
var _flags: ItemFlags
var _popup: GamePopup
var _item_popup: ItemDetailPopup
var _backdrop: Backdrop
var _top_bar: TopBar
var _tab_bar: TabBarView
var _toast: Toast
var _fx_layer: Control
## 突破充能动画（breakthrough_fx 的 charge）的长度。
const CHARGE_SECONDS := 2.0
var _page_host: MarginContainer
var _home_page: HomePage
var _stage_page: StagePage
var _battle_page: BattlePage
var _breakthrough_page: BreakthroughPage
## 突破弹窗层（全屏遮罩 + 居中弹窗，盖在当前页上面、顶栏和底栏下面也遮住）。
var _break_layer: Control
var _break_open := false
var _break_gen := 0
var _page_before_break := PAGE_CULTIVATE
var _bag_page: BagPage
var _skill_page: SkillPage
var _cave_page: CavePage
var _offline_popup: OfflinePopup
var _success_popup: BreakthroughSuccess
var _pages: Dictionary = {}
var _mock_tag: Label
var _offline_shown_id := ""
var _heartbeats := 0
var _last_inset := Vector4(-1, -1, -1, -1)
var _last_view := Vector2.ZERO
var _update_service: UpdateService
var _update_prompt: UpdatePrompt
## 后台公告：心跳 /me/state.notices → 排队，一次弹一条（不打断战斗、突破和其他弹窗）。
var _notices := NoticeQueue.new()
var _announcement: AnnouncementPrompt


func _ready() -> void:
	theme = APP_THEME
	_mock = UiMock.enabled()
	_hide_legacy_nodes()
	ScrollKit.install(self)  # v14：所有滚动区域隐藏滚动条 + 手指拖动 / 惯性（含之后新建的弹窗列表）
	_build_shell()
	get_viewport().size_changed.connect(_apply_layout)
	_show_page(PAGE_CULTIVATE)
	_login = PlayerLogin.new()
	_login.logged_in.connect(_on_logged_in)
	_login.z_index = Z_LOGIN
	add_child(_login)
	_setup_update_check()
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
		Catalog.apply(_content)
		_state = ProtoMock.state() if ProtoMock.available() else UiMock.state()
		_timer.wait_time = heartbeat_seconds(_state)
		_timer.start()
		_render()
		_maybe_show_offline()
		_sync_notices(_state.get("notices", []))
	elif PlayerApi.token().is_empty():
		_login.show()
		_set_status("请先登录。")
	else:
		_login.hide()
		_timer.start()
		_refresh_state()


## 客户端更新：启动时（登录页或已登录都一样）静默检查 <服务器地址>/download/latest.json，
## 有更高 versionCode 就弹「发现新版本」。演示模式不连服务器，除非 XIUXIAN_UPDATE_CHECK=1。
func _setup_update_check() -> void:
	_update_service = get_node_or_null("UpdateService") as UpdateService
	if _update_service == null:
		_update_service = UpdateService.new()
		_update_service.name = "UpdateService"
		add_child(_update_service)
	_update_prompt = UpdatePrompt.new(_popup, _update_service)
	_update_service.update_available.connect(func(info: Dictionary) -> void:
		_update_prompt.show_update(info, _update_service.get_current_version()))
	_check_update()


func _check_update() -> void:
	if OS.get_environment("XIUXIAN_UPDATE_CHECK") == "0":
		return
	if _mock and OS.get_environment("XIUXIAN_UPDATE_CHECK") != "1":
		return
	if _popup.visible:
		return
	_update_service.check_for_update(true)


## 应用切到后台：停心跳（服务器会把这段算离线）；回到前台：马上补一次心跳再恢复定时。
func _notification(what: int) -> void:
	if _timer == null or _mock:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_timer.stop()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_check_update()
		if not PlayerApi.token().is_empty():
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
	_battle_page.submit_requested.connect(_on_battle_submit)
	_battle_page.back_requested.connect(func() -> void: _show_page(PAGE_ADVENTURE))
	_battle_page.retry_requested.connect(_open_battle)
	_breakthrough_page = BreakthroughPage.new()
	_breakthrough_page.start_requested.connect(_on_breakthrough)
	_breakthrough_page.close_requested.connect(_close_breakthrough)
	_breakthrough_page.goto_stage_requested.connect(func(slug: String) -> void:
		_close_breakthrough()
		_select_stage(slug)
		_show_page(PAGE_ADVENTURE))
	_bag_page = BagPage.new()
	_bag_page.popup = _popup
	_bag_page.action_requested.connect(_on_page_action)
	_skill_page = SkillPage.new()
	_cave_page = CavePage.new()
	_cave_page.back_requested.connect(func() -> void: _show_page(PAGE_CULTIVATE))
	_pages = {PAGE_CULTIVATE: _home_page, PAGE_ADVENTURE: _stage_page, PAGE_BATTLE: _battle_page, PAGE_BREAKTHROUGH: _breakthrough_page, PAGE_BAG: _bag_page, PAGE_SKILL: _skill_page, PAGE_CAVE: _cave_page}
	for key in _pages:
		(_pages[key] as Control).visible = false
		if key != PAGE_BREAKTHROUGH:
			_page_host.add_child(_pages[key])
	_top_bar = TopBar.new()
	_top_bar.settings_pressed.connect(func() -> void: CreditsView.show_credits(_popup))
	_top_bar.z_index = Z_BARS
	add_child(_top_bar)
	_tab_bar = TabBarView.new()
	_tab_bar.set_tabs([
		{"id": PAGE_CULTIVATE, "name": "修炼", "icon": "tab_cultivate"},
		{"id": PAGE_ADVENTURE, "name": "历练", "icon": "tab_adventure"},
		{"id": PAGE_BREAKTHROUGH, "name": "突破", "center": true},
		{"id": PAGE_SKILL, "name": "功法", "icon": "tab_skill"},
		{"id": PAGE_BAG, "name": "背包", "icon": "tab_bag"},
	] as Array[Dictionary], PAGE_CULTIVATE)
	_tab_bar.page_selected.connect(_show_page)
	_tab_bar.center_pressed.connect(_on_center_pressed)
	_top_bar.breakthrough_pressed.connect(_on_center_pressed)
	_tab_bar.z_index = Z_BARS
	add_child(_tab_bar)
	# 特效层（掉落物飞进背包等跨页面的动画）：在页面和底栏之上、弹窗之下，不拦截点击。
	_fx_layer = Control.new()
	_fx_layer.name = "FxLayer"
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.z_index = Z_FX
	add_child(_fx_layer)
	_break_layer = Control.new()
	_break_layer.name = "BreakthroughLayer"
	_break_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_break_layer.visible = false
	var dim := ColorRect.new()
	dim.name = "Dimmer"
	# 有动画外壳时遮罩由弹窗自己画（淡入淡出），这一层只接「点空白处关闭」
	dim.color = Color(0, 0, 0, 0) if _breakthrough_page.has_popup_fx() else Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and not _busy:
			_close_breakthrough())
	_break_layer.add_child(dim)
	_break_layer.add_child(_breakthrough_page)
	_break_layer.z_index = Z_BREAK
	add_child(_break_layer)
	_toast = Toast.new()
	_toast.z_index = Z_TOAST
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
		_mock_tag.z_index = Z_TOAST
		add_child(_mock_tag)
	_popup.z_index = Z_POPUP
	add_child(_popup)
	# 物品详情（Q 版设计稿 q_popup_*，可换皮的独立场景）；在通用弹层之后加，二次确认等仍可盖在它上面（它会先关）。
	_item_popup = (ITEM_POPUP_SCENE.instantiate() as ItemDetailPopup)
	_item_popup.z_index = Z_POPUP
	add_child(_item_popup)
	_bag_page.detail_popup = _item_popup
	_offline_popup = OfflinePopup.new()
	_offline_popup.acknowledged.connect(_on_offline_ack)
	_offline_popup.z_index = Z_POPUP
	add_child(_offline_popup)
	_success_popup = BreakthroughSuccess.new()
	_success_popup.closed.connect(func() -> void:
		_close_breakthrough()
		_show_page(PAGE_CULTIVATE))
	_success_popup.z_index = Z_POPUP
	add_child(_success_popup)
	_announcement = AnnouncementPrompt.new(_popup)
	_announcement.acknowledged.connect(_on_notice_ack)
	_popup.closed.connect(func() -> void: _maybe_show_notice.call_deferred())
	_apply_layout()


## 按安全区排布顶部栏、内容区和底部页签。桌面上安全区为 0。
func _apply_layout() -> void:
	var inset := UiSafeArea.current(get_viewport())
	if OS.is_debug_build() and (inset != _last_inset or get_viewport_rect().size != _last_view):
		_last_inset = inset
		_last_view = get_viewport_rect().size
		print("[layout] 视口 %s  窗口 %s  安全区(左,上,右,下) %s" % [_last_view, DisplayServer.window_get_size(), inset])
	_top_bar.apply_safe_area(inset)
	_tab_bar.apply_safe_area(inset)
	_page_host.offset_left = float(UiTokens.PAGE_MARGIN) + inset.x
	_page_host.offset_right = -(float(UiTokens.PAGE_MARGIN) + inset.z)
	_page_host.offset_top = inset.y + _top_bar.content_height() + float(UiTokens.SP_1)
	_page_host.offset_bottom = -(float(TabBarView.HEIGHT) + TabBarView.bottom_pad(inset) + float(UiTokens.SP_2))
	_toast.place_top(float(UiTokens.PAGE_MARGIN) + inset.x, inset.y + _top_bar.content_height() + float(UiTokens.SP_2), float(UiTokens.PAGE_MARGIN) + inset.z, 110.0)
	_breakthrough_page.apply_safe_area(inset)
	_offline_popup.apply_safe_area(inset)
	if _item_popup != null:
		_item_popup.set_safe_top(inset.y)
	if _mock_tag != null:
		_mock_tag.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_mock_tag.offset_left = float(UiTokens.PAGE_MARGIN) + inset.x
		_mock_tag.offset_right = _mock_tag.offset_left + 88.0
		_mock_tag.offset_top = inset.y + 2.0
		_mock_tag.offset_bottom = _mock_tag.offset_top + 46.0


func _show_page(page: String) -> void:
	if page == PAGE_BREAKTHROUGH:
		_open_breakthrough()
		return
	if _page == PAGE_BATTLE and page != PAGE_BATTLE and _battle_page.is_running():
		_toast.say("战斗进行中，打完再离开", false)
		return
	if _break_open:
		_close_breakthrough()
	_page = page
	for key in _pages:
		if key != PAGE_BREAKTHROUGH:
			(_pages[key] as Control).visible = key == page
	_tab_bar.select(str(TAB_OF.get(page, page)))
	_backdrop.show_background(str(PAGE_BACKGROUNDS.get(page, "home")))
	_top_bar.set_cultivation_visible(page in PAGES_WITH_CULTIVATION)
	_apply_layout()
	var page_node := _pages[page] as Control
	_backdrop.set_sheet_anchor(page_node.call("sheet_anchor") if page_node.has_method("sheet_anchor") else null, float(page_node.call("sheet_pad")) if page_node.has_method("sheet_pad") else 52.0)
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
			Catalog.apply(_content)
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
	_sync_notices(state.get("notices", []))


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
			_enrich_drops((last as Dictionary).get("drops", []))
			var lines := WaveView.feedback(last as Dictionary, _reward_name)
			if not lines.is_empty():
				_home_page.show_feedback(lines)
			_home_page.show_gains(last as Dictionary)
			_fly_drops(lines)
			_stage_drops()
	_flags.adopt_if_first_run(_item_ids())
	_bag_page.bind(_state, _content, _flags)
	_stage_render()
	_skill_page.bind(_state, _content)
	_breakthrough_page.bind(_state, _content, next_name, _realm_after(BagModel.plain(breakthrough.get("nextSlug", null))))
	_update_dots()


## 掉落物飞进底栏背包（float_drop/drop_fly + bag_pulse，README 3b/3c）：只在修炼页、只飞这次结算真的进了背包的物品
## （最多 3 件；背包满没拿到的不飞）。起点 = 波次卡片掉落行里的物品格，终点 = 底栏背包图标；到达时背包图标跳一下。
func _fly_drops(lines: Array[Dictionary]) -> void:
	if _page != PAGE_CULTIVATE or not _home_page.is_visible_in_tree() or not QFx.has(QFx.DROP_FLY):
		return
	var drops := lines.filter(func(l: Dictionary) -> bool: return str(l.get("kind", "")) == "drop")
	if drops.is_empty():
		return
	var starts := _home_page.drop_slot_centers()
	var target := _tab_bar.icon_center("bag")
	var fallback := _home_page.sheet_anchor().get_global_rect().get_center()
	var shown := drops.slice(maxi(0, drops.size() - 3))
	for index in shown.size():
		var line: Dictionary = shown[index]
		var view := QKit.reward_view(_content, str(line.get("slug", "")))
		if view.texture == null:
			continue
		var fly := QFx.make(QFx.DROP_FLY) as Node2D
		fly.name = "DropFly"
		fly.set("icon", view.texture)
		fly.set("icon_size", 100.0)
		_fx_layer.add_child(fly)
		var start: Vector2 = starts[mini(index, starts.size() - 1)] if not starts.is_empty() else fallback
		fly.connect("arrived", func() -> void: _tab_bar.pulse("bag"))
		get_tree().create_timer(0.2 * index).timeout.connect(func() -> void:
			if is_instance_valid(fly):
				fly.call("fly", start, target))


## 历练页挂机特效：这次结算真的进了背包的掉落（不含背包满没拿到 / 自动分解的），下一只怪死时从怪身上弹出、飞进底栏「背包」。
## 只在历练页可见时传（不在历练页时攒着会在之后凭空弹出）；最多 3 件。
func _stage_drops() -> void:
	if _page != PAGE_ADVENTURE or not _stage_page.is_visible_in_tree():
		return
	var icons: Array[Texture2D] = []
	var last: Dictionary = _state.get("lastSettle", {}) if typeof(_state.get("lastSettle", null)) == TYPE_DICTIONARY else {}
	for row in last.get("drops", []):
		if typeof(row) != TYPE_DICTIONARY or bool((row as Dictionary).get("dropped", false)) or bool((row as Dictionary).get("decomposed", false)):
			continue
		var view := QKit.reward_view(_content, str((row as Dictionary).get("itemSlug", "")))
		if view.texture != null and icons.size() < 3:
			icons.append(view.texture)
	if icons.is_empty():
		return
	_stage_page.set_bag_target(_tab_bar.label_center("bag"))
	_stage_page.queue_drops(icons)


## 下一境界之后再下一个境界的名字（突破页第三个节点）；没有返回空串。
func _realm_after(slug: String) -> String:
	var rows: Array = _content.get("realms", [])
	for index in rows.size():
		if typeof(rows[index]) == TYPE_DICTIONARY and str((rows[index] as Dictionary).get("slug", "")) == slug and index + 1 < rows.size():
			return str((rows[index + 1] as Dictionary).get("displayName", ""))
	return ""


func _stage_render() -> void:
	# 历练页列出当前境界已解锁的全部关卡（有首领的可挑战，没有首领的只刷怪），再加一张下一个未解锁关卡的锁定卡。
	var stages := _stages_for_current_realm()
	# 换了境界（突破后）就重新选默认关卡：新解锁的首领关优先。
	var realm_now := str(_state.get("realmSlug", ""))
	if realm_now != _selected_realm:
		_selected_realm = realm_now
		_selected_stage = ""
	var known := false
	for stage in stages:
		if str(stage.get("slug", "")) == _selected_stage:
			known = true
	if not known:
		# 默认选中最高的首领关；一个首领关都没有就选最高的关卡。
		var pick_boss := ""
		var pick_last := ""
		for stage in stages:
			pick_last = str(stage.get("slug", ""))
			if not (stage.get("bosses", []) as Array).is_empty():
				pick_boss = pick_last
		_selected_stage = pick_boss if not pick_boss.is_empty() else pick_last
	_stage_page.bind(_state, _content, stages, _selected_stage, _next_locked_boss(), _next_locked_stage())


## 页签红点：能突破、背包里有新物品、有更强的装备可换。
func _update_dots() -> void:
	var view := BreakthroughView.build(_state)
	var gain := float((_state.get("cultivationRate", {}) as Dictionary).get("gainPerTick", 0)) if typeof(_state.get("cultivationRate", null)) == TYPE_DICTIONARY else 0.0
	_tab_bar.set_center("max" if not bool(view.has_next) else ("ready" if bool(view.can_start) else "hint"), _realm_name(BagModel.plain(_breakthrough_info().get("nextSlug", null))) if bool(view.has_next) else "已圆满")
	_tab_bar.set_dot(PAGE_CULTIVATE, false)
	_tab_bar.set_dot(PAGE_ADVENTURE, gain > 0.0 and bool(view.cultivation_ok) and not bool(view.boss_ok))
	var bag := BagModel.from_state(_state, _content, _flags.seen)
	var fresh := false
	for item in bag.items:
		if not bool(item.get("equipped", false)) and bool(item.get("is_new", false)) and _page != PAGE_BAG:
			fresh = true
	_tab_bar.set_dot(PAGE_BAG, fresh or not EquipModel.best_upgrades(bag).is_empty())
	_tab_bar.set_dot(PAGE_SKILL, false)


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


## 点「领取」（或关闭 / 点空白处）：告诉服务器已读（修为早已入账），成功才关；失败留着可再点。
func _on_offline_ack(report_id: String) -> void:
	var result := await _post("/api/v1/me/offline-reports/%s/ack" % report_id.uri_encode())
	if int(result.get("code", 0)) != 200:
		_toast.say(PlayerApi.error_message(result), false)
		_offline_popup.claim_button().disabled = false
		return
	_offline_popup.close_popup()
	_maybe_show_notice.call_deferred()
	if _state.get("offlineReport", null) != null and str((_state.get("offlineReport", {}) as Dictionary).get("id", "")) == report_id:
		_state["offlineReport"] = null


# ───────── 后台公告 ─────────

func _sync_notices(notices: Variant) -> void:
	_notices.sync(notices if typeof(notices) == TYPE_ARRAY else [])
	_maybe_show_notice()


## 有排队的公告、且眼下没有别的弹窗 / 突破 / 战斗时才弹；否则等下次心跳或弹窗关掉再试。
func _maybe_show_notice() -> void:
	if _notices.current.is_empty() or _announcement == null or not _announcement.showing_id.is_empty():
		return
	if _popup.visible or _offline_popup.visible or _item_popup.visible or _success_popup.visible or _break_open or _login.visible:
		return
	if _page == PAGE_BATTLE and _battle_page.is_running():
		return
	_announcement.show_notice(_notices.current)


func announcement_queue() -> NoticeQueue:
	return _notices


func _on_notice_ack(notice_id: String) -> void:
	if str(_notices.current.get("id", "")) == notice_id:
		_notices.close_current(true)
	if not _mock and not PlayerApi.token().is_empty():
		var result := await PlayerApi.dismiss_notice(PlayerApi.token(), notice_id)
		if int(result.get("code", 0)) >= 300 and OS.is_debug_build():
			print("[notice] 公告已读没告诉服务器：", PlayerApi.error_message(result))
	_maybe_show_notice.call_deferred()


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
		_battle_page.show_submit_error(PlayerApi.error_message(result))
		return
	_enrich_drops(result.get("drops", []))
	_apply_action_state(result)
	_battle_page.show_result(result, _reward_name)
	if bool(result.get("bagFull", false)):
		var full_bag := BagModel.from_state(_state, _content, {})
		_show_bag_full(full_bag.used_slots(), full_bag.capacity)


# ───────── 突破 ─────────

## 底栏突破钮 / 顶栏修为条右侧状态钮：已到最高境界不响应（按钮本身也禁用）；其余打开突破弹窗
## （条件不满足时弹窗里写清差什么，开始按钮不可点，并给「前往挑战」）。
func _on_center_pressed() -> void:
	var view := BreakthroughView.build(_state)
	if not bool(view.has_next):
		_toast.say_neutral(str(view.hint))
		return
	if not bool(view.can_start):
		_toast.say_neutral(str(view.hint))
	_open_breakthrough()


func _open_breakthrough() -> void:
	if not _break_open:
		_page_before_break = _page
	_break_open = true
	_break_gen += 1
	_break_layer.visible = true
	_breakthrough_page.visible = true
	_breakthrough_page.pop_in()


## 关闭突破弹窗：逻辑上立刻关（breakthrough_open() 变 false），画面播完关闭动画再隐藏。
func _close_breakthrough() -> void:
	if not _break_open:
		return
	_break_open = false
	_break_gen += 1
	var gen := _break_gen
	_breakthrough_page.pop_out(func() -> void:
		if gen == _break_gen and not _break_open:
			_break_layer.visible = false
			_breakthrough_page.visible = false)


func breakthrough_open() -> bool:
	return _break_open


func _on_breakthrough() -> void:
	if _busy:
		return
	_busy = true
	_breakthrough_page.set_busy(true)
	var before := _state.duplicate(true)
	var unlocks := BreakthroughView.unlocks(before, _content)
	# 充能动画和请求同时开始；成功要等充能播完再播成功特效，最后弹「突破成功」结算
	_breakthrough_page.play_charge()
	var started := Time.get_ticks_msec()
	var result := await _post("/api/v1/me/breakthrough")
	if int(result.get("code", 0)) != 200:
		_busy = false
		_breakthrough_page.finish_fx()
		_render()
		_toast.say(PlayerApi.error_message(result), false)
		return
	var outcome: Dictionary = result.get("result", {})
	_apply_action_state(result)
	if bool(outcome.get("success", false)):
		var left := CHARGE_SECONDS - float(Time.get_ticks_msec() - started) / 1000.0
		if _breakthrough_page.break_fx() != null and left > 0.0:
			await get_tree().create_timer(left).timeout
		await _breakthrough_page.play_success()
		_busy = false
		_breakthrough_page.finish_fx()
		_success_popup.show_success(BreakthroughView.success_summary(before, _state), unlocks)
	else:
		_busy = false
		_breakthrough_page.finish_fx()
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


func _breakthrough_info() -> Dictionary:
	return _state.get("breakthrough", {}) if typeof(_state.get("breakthrough", null)) == TYPE_DICTIONARY else {}


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


func _realm_name_of_order(order: int) -> String:
	for row in _content.get("realms", []):
		if typeof(row) == TYPE_DICTIONARY and int((row as Dictionary).get("sortOrder", -1)) == order:
			return str((row as Dictionary).get("displayName", ""))
	return ""


## 当前境界还打不到的最近一个关卡（want_boss = true 时只找有首领的）：
## {stage, boss, monster, realm, power}（没有返回空字典）。历练页用它显示锁定卡和“哪个境界解锁哪个首领”。
func _nearest_locked(want_boss: bool) -> Dictionary:
	var code := _current_realm_code()
	if code < 0:
		return {}
	var best: Dictionary = {}
	var best_code := 0
	for row in _content.get("stages", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var stage := row as Dictionary
		var stage_code := int(stage.get("requiredRealmOrder", -1))
		if stage_code <= code:
			continue
		if want_boss and (stage.get("bosses", []) as Array).is_empty():
			continue
		if best.is_empty() or stage_code < best_code:
			best = stage
			best_code = stage_code
	if best.is_empty():
		return {}
	var boss_rows: Array = best.get("bosses", [])
	var monsters: Array = best.get("monsters", [])
	return {
		"stage": str(best.get("displayName", best.get("slug", ""))),
		"boss": str((boss_rows[0] as Dictionary).get("name", "")) if not boss_rows.is_empty() and typeof(boss_rows[0]) == TYPE_DICTIONARY else "",
		"monster": str((monsters[0] as Dictionary).get("name", "")) if not monsters.is_empty() and typeof(monsters[0]) == TYPE_DICTIONARY else "",
		"realm": _realm_name_of_order(best_code),
		"power": int(best.get("recommendedPower", 0)),
	}


func _next_locked_boss() -> Dictionary:
	return _nearest_locked(true)


func _next_locked_stage() -> Dictionary:
	return _nearest_locked(false)


func _stage_def(slug: String) -> Dictionary:
	for row in _content.get("stages", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == slug:
			return row
	return {}


## 服务器返回的掉落行不带品质，按内容里的物品定义补上（界面按品质上色）。
func _enrich_drops(rows: Variant) -> void:
	if typeof(rows) != TYPE_ARRAY:
		return
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("quality", "")).is_empty():
			var quality := str(_item_def(str((row as Dictionary).get("itemSlug", ""))).get("quality", ""))
			if not quality.is_empty():
				(row as Dictionary)["quality"] = quality


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
