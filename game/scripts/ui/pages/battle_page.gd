class_name BattlePage
extends VBoxContainer
## 首领战斗页（第四批，SPEC_Q §17.1 / 设计稿 q_battle_boss_1080x2340.png）：
##   顶行（撤退 · 章节·关 绶带 · 限时胶囊）→ 首领 HUD（头像 + 首领名牌 + 境界 + 战力 + 首领大血条）
##   → 场景（首领主视觉、玩家、倍速按钮、开始挑战）→ 玩家 HUD（血条 + 属性）→ 战报（最多 4 行）。
## 战斗永远自动：不画技能冷却条、充能圆盘，也没有「自动战斗」开关和「战斗速度」行；倍速在场景右下角。
## 蓄力只驱动主角脚下聚气环，不在 HUD 上显示百分比或冷却提示。
## 不再区分精英战 / 首领战：标题、名牌、光圈一律首领样式（后台 tier 只剩外观用途，这里也统一按首领显示）。
## 战斗画面由 BossFight 在本地预演（公式与服务器一致），胜负和掉落以服务器返回为准；挑战请求不再带 ultTaps。
## 美术（SPEC_Q §17.8 / §17.10）：每章竖版战斗背景 bg_battle_<章>_1080x1640（章节 battleBgKey，没配跟随 bgKey，见 ArtLib.battle_bg_name）、
## 主角战斗姿势 sprites/player_fight.png（朝右）、统一首领立绘 sprites/boss_<怪>.png（已带首领描边）。
## 精英 / 章末两套切图（plate_elite、elite_*、chief_*）已废弃，不再引用。

signal submit_requested(stage_slug: String)
signal back_requested
signal retry_requested(stage_slug: String)
## 点了「撤退」。running=true 时由外面弹确认（撤退将视为挑战失败），确认后调 abort()。
signal retreat_requested(running: bool)

enum Phase { READY, RUNNING, SUBMITTING, RESULT }

## 首领战特效（anim_q/battle_boss）：登场、飞剑、受击闪白、震屏、伤害数字、血条白色残影、胜负表现。
## 没有大招按钮、没有手动放技能入口。万剑只在自动战斗事件 kind:ult 到来时由特效播放。
## 蓄力只调 _fx.set_skill_charge；刷新首领血量时一并 _fx.set_boss_hp_ratio（低于 30% 身冒红光）。
const BossBattleFx := preload("res://anim_q/battle_boss/boss_battle.tscn")
## 统一首领外观（monster_rig Tier.CHIEF）。
const TIER_CHIEF := 2
## 主角战斗姿势（SPEC_Q §17.8）：res://assets/art/q/sprites/player_fight.png，朝右，显示 390×390；没有就退回动画主角。
const HERO_POSE_HOOK := "player_fight"
const HERO_SIZE := 390.0
## 外壳底栏中间按钮上凸的高度（战斗页保留外壳底栏，见第四批改动说明）。
const TAB_OVERHANG := 64.0
## 主角整体抬高（负责人：脚要完整露出、踩在地面上，40–90px）：战斗区下沿被下方面板的圆角 / 阴影压住一截，
## 立绘脚底在图内 y≈600/635（SPEC_Q §17.8），抬 60px 后脚底离战斗区下沿约 80px。
const HERO_RAISE := 60.0
## 战报最多显示几行（最新在最上，超出顶掉最旧，不滚动）。
const REPORT_ROWS := 4
const SPEED_PREF_PATH := "user://battle_prefs.cfg"
const REPORT_CHIPS := {
	"ult": {"text": "自动技能", "color": Color("ffa43a")},
	"hit": {"text": "攻击", "color": Color("5aaeff")},
	"hurt": {"text": "受击", "color": Color("ff5e5e")},
	"info": {"text": "开战", "color": Color("7ed36a")},
	"end": {"text": "结算", "color": Color("7ed36a")},
}

var _fx: Node2D

var phase := Phase.READY
var fight: BossFight
var speed := 1.0
var stage_slug := ""

var _state: Dictionary = {}
var _content: Dictionary = {}
var _stage: Dictionary = {}
var _gate: Dictionary = {}
var _boss_name := ""
var _ult_name := "自动技能"
var _clock := 0.0
var _title: Label
var _timer_text: Label
var _boss_portrait_host: Control
var _boss_name_label: Label
var _boss_realm: Label
var _boss_power: Label
var _boss_bar: BossHpBar
var _me_name: Label
var _me_realm: Label
var _me_power: Label
var _me_bar_host: Control
var _me_stats: Label
var _arena: Control
var _boss_art: TextureRect
var _hero_art: TextureRect
var _hero_base: Texture2D
var _player_avatar: TextureRect
var _avatar_base: Texture2D
var _float_layer: Control
var _report: BattleReport
var _feed: VBoxContainer
var _speed_button: TextureButton
var _speed_fallback: Label
var _start_button: Button
var _result_panel: PanelContainer
var _controls: Control
var _result_body: VBoxContainer
var _report_lines := 0
var _last_time_text := ""
## 大招已经结算、但剑扇还没打到首领的伤害：血条先不扣，等特效 ult_landed 再扣（血条和剑同步）
var _ult_pending := 0.0


func _init() -> void:
	add_theme_constant_override("separation", UiTokens.SP_1)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_build_top_row())
	add_child(_build_boss_hud())
	_build_arena()
	add_child(_result_panel)
	_controls = _build_player_hud()
	add_child(_controls)
	add_child(_build_report_panel())
	# 底部留白：外壳底栏中间的大按钮会往上凸，别压住战报最后一行
	var tail := Control.new()
	tail.name = "TabOverhangSpacer"
	tail.custom_minimum_size = Vector2(0, TAB_OVERHANG)
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tail)
	_load_speed()
	resized.connect(queue_redraw)
	_arena.resized.connect(queue_redraw)


# ───────── 版式 ─────────

## 顶行：撤退（btn_back + 「撤退」）· 绶带「章节·关」· 限时胶囊（沙漏 + 剩余时间）。
func _build_top_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "TopRow"
	row.add_theme_constant_override("separation", UiTokens.SP_1)
	row.custom_minimum_size = Vector2(0, 112)
	var retreat := VBoxContainer.new()
	retreat.name = "Retreat"
	retreat.add_theme_constant_override("separation", -8)
	var back := TextureButton.new()
	back.name = "RetreatButton"
	back.texture_normal = ArtLib.qui("btn_back")
	back.ignore_texture_size = true
	back.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	back.custom_minimum_size = Vector2(96, 90)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_on_retreat)
	retreat.add_child(back)
	var word := QKit.outlined("撤退", 30, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 7, HORIZONTAL_ALIGNMENT_CENTER)
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	retreat.add_child(word)
	row.add_child(retreat)
	var mid := CenterContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ribbon := QKit.ribbon("", 46, 300, false)
	ribbon.name = "TitleRibbon"
	_title = ribbon.find_child("RibbonText", true, false) as Label
	_title.name = "Title"
	mid.add_child(ribbon)
	row.add_child(mid)
	var timer_row := UiKit.hbox(6)
	timer_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_row.add_child(QKit.cut_rect("icon_hourglass", Vector2(48, 52)))
	_timer_text = QKit.outlined("0:45", 44, UiTokens.TEXT, UiTokens.Q_CREAM, 0, HORIZONTAL_ALIGNMENT_CENTER, false)
	_timer_text.name = "TimerText"
	_timer_text.custom_minimum_size = Vector2(110, 0)
	timer_row.add_child(_timer_text)
	var pill := QKit.pill(UiTokens.Q_CREAM, timer_row, 4, 5, 18, 4)
	pill.name = "TimerPill"
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pill)
	return row


## 首领 HUD：panel_cream；头像圆 + ring_chief_204 + badge_chief；名牌 plate_chief（「首领」）+ 名字 + 境界胶囊 + 战力；大血条。
func _build_boss_hud() -> Control:
	var made := QKit.panel(UiTokens.Q_CREAM, 34, 18, 12, 4, 6, "panel_cream")
	var card := made.panel as PanelContainer
	card.name = "BossHud"
	var body := made.body as VBoxContainer
	var row := UiKit.hbox(UiTokens.SP_1)
	body.add_child(row)
	_boss_portrait_host = Control.new()
	_boss_portrait_host.name = "BossPortrait"
	_boss_portrait_host.custom_minimum_size = Vector2(170, 170)
	_boss_portrait_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_boss_portrait_host)
	var column := UiKit.vbox(8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(column)
	var head := UiKit.hbox(10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(head)
	var plate := QKit.cut_rect("plate_chief", Vector2(150, 46))
	plate.name = "BossPlate"
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if plate is TextureRect:
		pass
	else:
		plate.add_child(QKit.tag("首领", "red"))
	head.add_child(plate)
	_boss_name_label = QKit.outlined("", 50, Color("ffe27a"), Color("8e2420"), 10)
	_boss_name_label.name = "BossName"
	_boss_name_label.clip_text = true
	_boss_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_boss_name_label)
	var realm_chip := QKit.tag("", "orange", 26)
	realm_chip.name = "BossRealm"
	_boss_realm = realm_chip.get_child(0) as Label
	head.add_child(realm_chip)
	_boss_power = UiKit.label("", 28, Color("b0614a"), HORIZONTAL_ALIGNMENT_RIGHT)
	_boss_power.name = "BossPower"
	head.add_child(_boss_power)
	_boss_bar = BossHpBar.new()
	column.add_child(_boss_bar)
	return card


func _build_arena() -> void:
	_arena = Control.new()
	_arena.name = "Arena"
	_arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_arena.custom_minimum_size = Vector2(0, 520)
	_arena.clip_contents = true
	_arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_arena)
	# 首领主视觉：居中、放大（设计稿倍率 1.3），脚底靠下
	_boss_art = TextureRect.new()
	_boss_art.name = "BossArt"
	_boss_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_boss_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_boss_art.anchor_left = 0.5
	_boss_art.anchor_right = 0.5
	_boss_art.anchor_top = 0.0
	_boss_art.anchor_bottom = 1.0
	_boss_art.offset_left = -250
	_boss_art.offset_right = 330
	_boss_art.offset_top = 10
	_boss_art.offset_bottom = -150
	_boss_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena.add_child(_boss_art)
	# 主角：左前方、比首领小。战斗姿势立绘优先（HERO_POSE_HOOK），没有就动画主角，再不行退回头像图标
	var hero := QHero.new(false, false)
	if ArtLib.has_q("sprites/%s.png" % HERO_POSE_HOOK):
		hero.free()
		_hero_art = _hero_rect(ArtLib.q("sprites/" + HERO_POSE_HOOK), Color.WHITE)
	elif hero.is_animated():
		hero.name = "BattleHero"
		_place_hero(hero)
		_arena.add_child(hero)
	else:
		hero.free()
		_hero_art = _hero_rect(ArtLib.icon("avatar_meditate"), UiTokens.GOLD_HOVER)
	_float_layer = Control.new()
	_float_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena.add_child(_float_layer)
	_fx = BossBattleFx.instantiate()
	_arena.add_child(_fx)
	if _fx.has_signal("ult_landed"):
		_fx.ult_landed.connect(func(_d: int) -> void:
			_ult_pending = 0.0
			_refresh_bars(true))
	_fx.attach(_arena, _arena.get_node_or_null("BattleHero") if _hero_art == null else _hero_art, _boss_art)
	# 倍速：右下角 btn_speed_x1 / x2 两态，下方「倍速」
	var speed_box := VBoxContainer.new()
	speed_box.name = "SpeedBox"
	speed_box.add_theme_constant_override("separation", -6)
	speed_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	speed_box.offset_left = -150
	speed_box.offset_right = -14
	speed_box.offset_top = -190
	speed_box.offset_bottom = -10
	_speed_button = TextureButton.new()
	_speed_button.name = "SpeedButton"
	_speed_button.ignore_texture_size = true
	_speed_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_speed_button.custom_minimum_size = Vector2(128, 136)
	_speed_button.focus_mode = Control.FOCUS_NONE
	_speed_button.pressed.connect(func() -> void: _set_speed(1.0 if speed > 1.5 else 2.0, true))
	speed_box.add_child(_speed_button)
	_speed_fallback = QKit.outlined("×1", 40, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 8, HORIZONTAL_ALIGNMENT_CENTER)
	_speed_fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speed_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_button.add_child(_speed_fallback)
	var speed_word := QKit.outlined("倍速", 30, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 7, HORIZONTAL_ALIGNMENT_CENTER)
	speed_word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_box.add_child(speed_word)
	_arena.add_child(speed_box)
	_start_button = UiKit.cta_button("开始挑战", "限时 45 秒", MainTheme.VAR_PRIMARY, 150)
	_start_button.name = "StartButton"
	_start_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_start_button.offset_left = -250
	_start_button.offset_right = 250
	_start_button.offset_top = -170
	_start_button.offset_bottom = -20
	_start_button.pressed.connect(_on_start)
	_arena.add_child(_start_button)
	_result_panel = PanelContainer.new()
	_result_panel.name = "ResultPanel"
	_result_panel.visible = false
	_result_panel.add_theme_stylebox_override("panel", ArtLib.nine("panel_popup"))
	_result_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_result_body = UiKit.vbox(UiTokens.SP_1)
	_result_panel.add_child(_result_body)


func _place_hero(node: Control) -> void:
	node.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	var side := HERO_SIZE if node.name == "HeroArt" else 300.0
	node.offset_left = -30
	node.offset_right = side - 30.0
	node.offset_top = -side - HERO_RAISE
	node.offset_bottom = -HERO_RAISE


func _hero_rect(tex: Texture2D, tint: Color) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = "HeroArt"
	rect.texture = tex
	rect.modulate = tint
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_hero(rect)
	_arena.add_child(rect)
	return rect


## 有 appearance 时换战斗整图和圆头像；没有或图缺失时保持现默认。
func apply_appearance(appearance: Variant) -> void:
	if _hero_art != null:
		if _hero_base == null:
			_hero_base = _hero_art.texture
		var preview := OutfitAppearance.texture(appearance, "preview")
		_hero_art.texture = preview if preview != null else _hero_base
		_hero_art.visible = true
	if _player_avatar != null:
		if _avatar_base == null:
			_avatar_base = _player_avatar.texture
		var round := OutfitAppearance.texture(appearance, "avatar_round")
		_player_avatar.texture = round if round != null else _avatar_base


## 玩家 HUD：头像 + 「我」+ 境界胶囊 + 战力；血条；属性行。右侧不留充能圆盘占位。
func _build_player_hud() -> Control:
	var made := QKit.panel(UiTokens.Q_CREAM, 34, 22, 12, 4, 6, "panel_cream")
	var card := made.panel as PanelContainer
	card.name = "PlayerHud"
	var row := UiKit.hbox(UiTokens.SP_2)
	row.name = "PlayerHudRow"
	(made.body as VBoxContainer).add_child(row)
	var avatar := QKit.cut_rect("avatar_player_round", Vector2(116, 116))
	avatar.name = "PlayerAvatar"
	if avatar is TextureRect:
		_player_avatar = avatar
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var frame := QKit.cut_rect("avatar_frame", Vector2(116, 116))
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	avatar.add_child(frame)
	row.add_child(avatar)
	var column := UiKit.vbox(8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(column)
	var head := UiKit.hbox(10)
	column.add_child(head)
	_me_name = QKit.title("我", 40, UiTokens.TEXT)
	_me_name.name = "MeName"
	head.add_child(_me_name)
	var chip := QKit.tag("", "mint", 26)
	chip.name = "MeRealm"
	_me_realm = chip.get_child(0) as Label
	head.add_child(chip)
	_me_power = UiKit.label("", 28, Color("b0614a"))
	_me_power.name = "MePower"
	head.add_child(_me_power)
	_me_bar_host = Control.new()
	_me_bar_host.name = "MeBar"
	_me_bar_host.custom_minimum_size = Vector2(0, 40)
	_me_bar_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_me_bar_host)
	_me_stats = UiKit.label("", 28, UiTokens.TEXT_MUTED)
	_me_stats.name = "MeStats"
	column.add_child(_me_stats)
	return card


## 战报：panel_cream + 压边绶带「战报」+ well_apricot，最多 4 行（类型胶囊 + 正文），最新在最上。
func _build_report_panel() -> Control:
	var made := QKit.panel(UiTokens.Q_CREAM, 34, 24, 10, 4, 6, "panel_cream")
	var panel := made.panel as PanelContainer
	panel.name = "ReportPanel"
	var body := made.body as VBoxContainer
	body.add_theme_constant_override("separation", 4)
	var ribbon := QKit.ribbon("战报", 36, 120, false)
	ribbon.name = "ReportRibbon"
	ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(ribbon)
	var well := PanelContainer.new()
	well.name = "ReportWell"
	well.add_theme_stylebox_override("panel", QKit.cut_box("well_apricot", 18, 10) if ArtLib.qui("well_apricot") != null else QSkin.custom(UiTokens.Q_CARD, Color(0, 0, 0, 0), 0, 24, 0, 18, 10))
	well.custom_minimum_size = Vector2(0, REPORT_ROWS * 54 + 24)
	_feed = UiKit.vbox(6)
	_feed.name = "ReportFeed"
	well.add_child(_feed)
	body.add_child(well)
	# 完整战报（服务器版本、测试 / 截图读文字用）：不显示
	_report = BattleReport.new()
	_report.name = "FullReport"
	_report.visible = false
	body.add_child(_report)
	return panel


# ───────── 打开 / 流程 ─────────

## 打开某个关卡的首领战。gate = BagModel.challenge_gate(...) 的结果。
func open_stage(state: Dictionary, content: Dictionary, stage: Dictionary, gate: Dictionary, my_realm_name: String) -> void:
	_state = state
	_content = content
	apply_appearance(state.get("appearance", null))
	_stage = stage
	_gate = gate
	stage_slug = str(stage.get("slug", ""))
	var bosses: Array = stage.get("bosses", [])
	var boss: Dictionary = bosses[0] if not bosses.is_empty() and typeof(bosses[0]) == TYPE_DICTIONARY else {}
	_boss_name = str(boss.get("name", "首领"))
	var ult_cfg: Variant = state.get("ult", {})
	_ult_name = _skill_display_name(str((ult_cfg as Dictionary).get("name", "")) if typeof(ult_cfg) == TYPE_DICTIONARY else "")
	fight = BossFight.from_state(state, content, stage)
	_push_skill_sources()
	_ult_pending = 0.0
	phase = Phase.READY
	_clock = 0.0
	_report_lines = 0
	_report.clear()
	UiKit.clear(_feed)
	_clear_floats()
	_result_panel.visible = false
	_arena.visible = true
	_controls.visible = true
	_start_button.visible = true
	_start_button.disabled = fight == null
	_title.text = title_text(stage)
	var limit := fight.time_limit if fight != null else 45.0
	UiKit.set_cta(_start_button, "开始挑战", "限时 %d 秒" % int(limit))
	_boss_name_label.text = _boss_name
	_boss_realm.text = StageAccessView._realm_name(content, int(stage.get("requiredRealmOrder", 0)))
	(_boss_realm.get_parent() as Control).visible = not _boss_realm.text.is_empty()
	_boss_power.text = "战力 %s" % QKit.grouped(float(stage.get("recommendedPower", 0))) if int(stage.get("recommendedPower", 0)) > 0 else ""
	_me_name.text = "我"
	_me_realm.text = my_realm_name
	(_me_realm.get_parent() as Control).visible = not my_realm_name.is_empty()
	_me_power.text = "战力 %s" % QKit.grouped(float(state.get("power", 0))) if int(state.get("power", 0)) > 0 else ""
	_me_stats.text = "攻 %s   防 %s   速 %.1f/秒" % [QKit.grouped(float(state.get("attack", 0))), QKit.grouped(float(state.get("defense", 0))), 1.0 / maxf(float(state.get("interval", 1.0)), 0.05)]
	# 首领立绘：Q 版怪物图（按后台 artKey 查，没有再按名字），朝左面向主角；认不出的首领退回旧剪影（染色）
	var sprite := boss_sprite_of(boss)
	if not sprite.is_empty():
		_boss_art.texture = ArtLib.q("sprites/" + sprite)
		_boss_art.modulate = Color.WHITE
		_boss_art.flip_h = ArtLib.monster_needs_flip(sprite)
	else:
		_boss_art.texture = ArtLib.icon(ArtLib.boss_icon_name(_boss_name))
		_boss_art.modulate = UiTokens.rarity_color(4).lightened(0.25)
		_boss_art.flip_h = false
	_set_portrait(boss)
	# 统一首领外观；名牌放在 HUD 里，场景里的首领头顶不再挂名牌
	_fx.tier = TIER_CHIEF
	if _fx.boss != null:
		_fx.boss.fx_variant = boss_fx_of(content, stage)
		if "show_plate" in _fx.boss:
			_fx.boss.show_plate = false
	_fx.set_boss_from_art()
	_refresh_bars(false)
	_refresh_ult()
	_refresh_time()
	if fight == null:
		_timer_text.text = "--"
		_append_feed("info", "这个关卡还没有首领")
		return
	_append_info("你（气血 %d）对阵 %s（气血 %d）" % [BagModel.shown(fight.player_max_hp), _boss_name, BagModel.shown(fight.boss_max_hp)])
	if int(stage.get("recommendedPower", 0)) > 0:
		_append_info("推荐战力 %d，我的战力 %d" % [int(stage.get("recommendedPower", 0)), int(state.get("power", 0))])
	_append_feed("info", "限时 %d 秒" % int(limit))


## 「章节 · 关」：displayName 本来就是「赤炎火山·三」这种写法，直接用；不再带「精英战 / 首领战」。
static func title_text(stage: Dictionary) -> String:
	return str(stage.get("displayName", ""))


## 首领战斗页用的立绘：统一首领立绘 boss_<怪> 优先（artKey 选了普通怪、但有同名 boss_* 时也换成 boss_*），没有再用 mon_*。
static func boss_sprite_of(boss: Dictionary) -> String:
	var sprite := ArtLib.monster_sprite_for(boss)
	if sprite.begins_with("mon_"):
		var unified := "boss_" + sprite.trim_prefix("mon_")
		if ArtLib.has_q("sprites/%s.png" % unified):
			return unified
	return sprite


## 战斗页底下的薄荷底板从玩家 HUD 上沿开始（同修炼页下半区）。
func sheet_anchor() -> Control:
	return _controls if _controls != null and _controls.visible else null


func sheet_pad() -> float:
	return 28.0


## 场景上下的暗色渐变（SPEC_Q §17.1：顶部 rgba(40,16,10,.55→0)、场景底部同色），保证 HUD 和白字在亮背景上可读。
func _draw() -> void:
	if _arena == null or not _arena.visible:
		return
	var dark := Color(40.0 / 255.0, 16.0 / 255.0, 10.0 / 255.0, 0.55)
	var clear := Color(dark, 0.0)
	var w := size.x
	var top_h := minf(420.0, size.y)
	draw_polygon(PackedVector2Array([Vector2(-40, -200), Vector2(w + 40, -200), Vector2(w + 40, top_h), Vector2(-40, top_h)]), PackedColorArray([dark, dark, clear, clear]))
	var bottom := _arena.position.y + _arena.size.y
	draw_polygon(PackedVector2Array([Vector2(-40, bottom - 220.0), Vector2(w + 40, bottom - 220.0), Vector2(w + 40, bottom), Vector2(-40, bottom)]), PackedColorArray([clear, clear, dark, dark]))


## 首领头像：怪物图放进圆里 + ring_chief_204 外圈 + badge_chief（旋转 18°）。
func _set_portrait(boss: Dictionary) -> void:
	UiKit.clear(_boss_portrait_host)
	var disc := QKit.portrait(_boss_name, 150, Color("ff4b3a"), false, BagModel.plain(boss.get("artKey", null)))
	disc.position = Vector2(10, 10)
	_boss_portrait_host.add_child(disc)
	var ring := QKit.cut_rect("ring_chief_204", Vector2(170, 170))
	ring.position = Vector2.ZERO
	ring.size = Vector2(170, 170)
	_boss_portrait_host.add_child(ring)
	var badge := QKit.cut_rect("badge_chief", Vector2(62, 54))
	badge.name = "BadgeChief"
	badge.position = Vector2(118, -14)
	badge.size = Vector2(62, 54)
	badge.pivot_offset = Vector2(31, 27)
	badge.rotation_degrees = 18.0
	_boss_portrait_host.add_child(badge)


## 这关所在章节的首领特效 key（content.chapters[].bossFx）；没有章节 / 没配 = default。
static func boss_fx_of(content: Dictionary, stage: Dictionary) -> String:
	var chapter := StageAccessView.chapter_row(content, BagModel.plain(stage.get("chapterSlug", null)))
	var fx := BagModel.plain(chapter.get("bossFx", null))
	return fx if not fx.is_empty() else "default"


func _find_title() -> Label:
	return _title


func is_running() -> bool:
	return phase == Phase.RUNNING


func _set_speed(value: float, remember: bool = false) -> void:
	speed = value
	var fast := value > 1.5
	var tex := ArtLib.qui("btn_speed_x2" if fast else "btn_speed_x1")
	_speed_button.texture_normal = tex
	_speed_fallback.visible = tex == null
	_speed_fallback.text = "×2" if fast else "×1"
	if remember:
		var cfg := ConfigFile.new()
		cfg.load(SPEED_PREF_PATH)
		cfg.set_value("battle", "speed", value)
		cfg.save(SPEED_PREF_PATH)


func _load_speed() -> void:
	var cfg := ConfigFile.new()
	var value := 1.0
	if cfg.load(SPEED_PREF_PATH) == OK:
		value = float(cfg.get_value("battle", "speed", 1.0))
	_set_speed(2.0 if value > 1.5 else 1.0)


func _on_start() -> void:
	if fight == null or phase != Phase.READY:
		return
	phase = Phase.RUNNING
	_clock = 0.0
	_start_button.visible = false
	# 先播「首领来袭」登场（约 1.75 秒）；登场期间 _process 不推进战斗时钟
	_fx.play_intro()
	_append_feed("info", "战斗开始")
	_report.add_line(BattleReport.Kind.PLAIN, "战斗开始", 0)
	if bool(_gate.get("full", false)):
		_append_info(GateNotice.text(_gate))


func _on_retreat() -> void:
	retreat_requested.emit(phase == Phase.RUNNING)


## 撤退确认后：本地预演作废，不提交（服务器没有这场记录，不占次数），回到就绪。
func abort() -> void:
	if phase != Phase.RUNNING:
		return
	phase = Phase.READY
	_append_feed("end", "已撤退，挑战失败")
	_start_button.visible = true
	_start_button.disabled = fight == null
	if fight != null:
		fight = BossFight.from_state(_state, _content, _stage)
	_ult_pending = 0.0
	_clock = 0.0
	_fx.set_boss_from_art()
	_refresh_bars(false)
	_refresh_ult()
	_refresh_time()


func _process(delta: float) -> void:
	if phase != Phase.RUNNING or fight == null or not is_visible_in_tree():
		return
	if _fx.is_intro_playing():
		return
	_advance(delta * speed)


## 测试 / 脚本：直接把时钟推进 seconds 秒（不依赖帧）。
func step(seconds: float) -> void:
	if phase != Phase.RUNNING or fight == null:
		return
	_advance(seconds)


func _advance(seconds: float) -> void:
	_clock += seconds
	fight.advance_to(_clock)
	_consume_events()
	_refresh_ult()
	_refresh_time()
	if fight.finished:
		phase = Phase.SUBMITTING
		_append_feed("end", "战斗结束，正在结算……")
		_fx.play_result(fight.win, fight.reason)
		submit_requested.emit(stage_slug)


func _consume_events() -> void:
	var events := fight.take_events()
	if events.is_empty():
		return
	for event in events:
		var line := BattleReportBuilder.live_line(event, _boss_name, _ult_name)
		_report.add_line(int(line.kind) as BattleReport.Kind, str(line.text), 0)
		_report_lines += 1
		_append_feed(feed_kind(event), feed_text(event, _boss_name, _ult_name))
		if str(event.get("kind", "")) == "ult" and _fx.has_signal("ult_landed"):
			_ult_pending += float(event.get("damage", 0))
		_fx.on_event(event)
	_refresh_bars(true)


## 配置里的技能显示名。空名，或仍写成「大招 / 暴击」时，玩家看到的是「自动技能」。
static func _skill_display_name(raw: String) -> String:
	return BattleReportBuilder._skill_name(raw)


## 事件 → 战报胶囊类型：自动技能 / 攻击 / 受击。
static func feed_kind(event: Dictionary) -> String:
	if str(event.get("side", "")) == "boss":
		return "hurt"
	return "ult" if str(event.get("kind", "")) == "ult" else "hit"


## 战报正文（伤害数字标红）。
static func feed_text(event: Dictionary, boss_name: String, ult_name: String) -> String:
	var dmg := "[color=#d93a3f]%s[/color]" % QKit.grouped(BagModel.shown(float(event.get("damage", 0))))
	var name := BattleReport.escape(boss_name if not boss_name.is_empty() else "首领")
	match feed_kind(event):
		"hurt":
			return "%s出手，你受到 %s 伤害" % [name, dmg]
		"ult":
			return "你施放「%s」，对%s造成 %s 伤害" % [BattleReport.escape(ult_name), name, dmg]
		_:
			return "你攻击%s，造成 %s 伤害" % [name, dmg]


## 战报加一行：类型胶囊 + 正文（BBCode），最新在最上，超过 REPORT_ROWS 行顶掉最旧。
func _append_feed(kind: String, bbcode: String) -> void:
	var spec: Dictionary = REPORT_CHIPS.get(kind, REPORT_CHIPS.info)
	var row := UiKit.hbox(12)
	row.name = "FeedRow"
	row.set_meta("kind", kind)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip := QKit.tag(str(spec.text), spec.color as Color, 24, 14)
	chip.custom_minimum_size = Vector2(88, 44)
	row.add_child(chip)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_OFF
	text.clip_contents = true
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_font_size_override("normal_font_size", 30)
	text.add_theme_color_override("default_color", UiTokens.TEXT)
	text.text = bbcode
	row.add_child(text)
	_feed.add_child(row)
	_feed.move_child(row, 0)
	while _feed.get_child_count() > REPORT_ROWS:
		var old := _feed.get_child(_feed.get_child_count() - 1)
		_feed.remove_child(old)
		old.queue_free()


## 眼下战报里显示的几行纯文字（最新在前）。
func feed_lines() -> Array[String]:
	var out: Array[String] = []
	for row in _feed.get_children():
		var rich := row.get_child(1) as RichTextLabel
		if rich != null:
			out.append(rich.get_parsed_text())
	return out


func _append_info(text: String) -> void:
	_report.add_line(BattleReport.Kind.PLAIN, text, 0)


func _refresh_bars(animate: bool = true) -> void:
	if fight == null:
		_set_me_bar(1.0, "-- / --")
		_boss_bar.set_hp(1.0, 1.0, false)
		_push_boss_hp_ratio(1.0)
		return
	var shown_hp := minf(fight.boss_hp + _ult_pending, fight.boss_max_hp)
	_set_me_bar(fight.player_hp / maxf(fight.player_max_hp, 1.0), "%s / %s" % [QKit.grouped(BagModel.shown(maxf(fight.player_hp, 0.0))), QKit.grouped(BagModel.shown(fight.player_max_hp))])
	_boss_bar.set_hp(shown_hp, fight.boss_max_hp, animate)
	_push_boss_hp_ratio(shown_hp / maxf(fight.boss_max_hp, 1.0))


## 首领血量比例交给特效：低于 30% 时身冒红光。没有手动释放入口。
func _push_boss_hp_ratio(ratio: float) -> void:
	if _fx != null and _fx.has_method("set_boss_hp_ratio"):
		_fx.set_boss_hp_ratio(ratio)


func _set_me_bar(ratio: float, text: String) -> void:
	UiKit.clear(_me_bar_host)
	var bar := QKit.bar(clampf(ratio, 0.0, 1.0), UiTokens.Q_MINT, 40, 1, UiTokens.Q_TRACK, "mint")
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_me_bar_host.add_child(bar)
	var label := QKit.outlined(text, 30, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 6, HORIZONTAL_ALIGNMENT_CENTER, false)
	label.name = "MeHpText"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_me_bar_host.add_child(label)


## 限时胶囊：剩余时间 m:ss。
func _refresh_time() -> void:
	if fight == null:
		return
	var used := minf(fight.t if not fight.finished else fight.duration, fight.time_limit)
	var left := maxi(0, int(ceil(fight.time_limit - used)))
	var text := "%d:%02d" % [left / 60, left % 60]
	if text != _last_time_text:
		_last_time_text = text
		_timer_text.text = text


## 把内容技能和运转中的技能交给特效层。只读配置，不在这里画充能或技能按钮。
func _push_skill_sources() -> void:
	if _fx == null or not _fx.has_method("set_skill_sources"):
		return
	var defs: Array = []
	var running: Array = []
	var raw_defs: Variant = _content.get("skills", [])
	var raw_running: Variant = _state.get("skills", [])
	if raw_defs is Array:
		defs = raw_defs
	if raw_running is Array:
		running = raw_running
	_fx.call("set_skill_sources", defs, running)


## 自动技能蓄力只推给脚下聚气环。不画冷却条或百分比。蓄满由战斗逻辑出事件。
func _refresh_ult() -> void:
	if fight == null or not fight.has_ult():
		_push_skill_charge(0.0, false)
		return
	var charging := phase == Phase.RUNNING
	_push_skill_charge(fight.ult_charge() if charging else 0.0, true)


## 自动技能蓄力（仅表现）。优先 set_skill_charge，没有该方法时退回遗留名 set_ult_charge。
func _push_skill_charge(value: float, learned: bool) -> void:
	if _fx == null:
		return
	if _fx.has_method("set_skill_charge"):
		_fx.set_skill_charge(value, learned)
	elif _fx.has_method("set_ult_charge"):
		_fx.call("set_ult_charge", value, learned)


## 飘字分「车道」：同一边的飘字依次占用不同高度（再左右错开），同时最多 FLOAT_MAX_PER_SIDE 条，
## 超出时最旧的直接收掉，避免挤成一串（v8 验收意见）。
const FLOAT_LANES := 4
const FLOAT_LANE_HEIGHT := 66.0
const FLOAT_MAX_PER_SIDE := 4
var _float_count := {"boss": 0, "hero": 0}


func _float_damage(event: Dictionary) -> void:
	var boss_side := str(event.get("side", "")) == "boss"
	var side := "boss" if boss_side else "hero"
	var ult := str(event.get("kind", "")) == "ult"
	var amount := BagModel.shown(float(event.get("damage", 0)))
	var label := UiKit.label("-%d" % amount, UiTokens.FS_H1 if ult else UiTokens.FS_BODY_L, UiTokens.DANGER if boss_side else (UiTokens.REPORT_CRIT if ult else UiTokens.REPORT_DAMAGE_DEALT), HORIZONTAL_ALIGNMENT_CENTER)
	## 伤害数字用美术位图字体（digits_dmg 普通 / digits_crit 大招），缺字体时退回标题字 + 描边。
	var digits := ArtLib.digits_font("crit" if ult else "dmg")
	if digits != null:
		label.add_theme_font_override("font", digits)
		label.add_theme_font_size_override("font_size", 84 if ult else 64)
		label.add_theme_color_override("font_color", Color.WHITE)  # 位图字体会乘字色，保持美术原色
		if boss_side:
			label.modulate = Color(1.0, 0.72, 0.72)
	else:
		label.add_theme_font_override("font", ArtLib.title_font())
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("outline_size", 10)
	label.set_meta("side", side)
	label.set_anchors_preset(Control.PRESET_CENTER_LEFT if boss_side else Control.PRESET_CENTER_RIGHT)
	var lane: int = int(_float_count[side]) % FLOAT_LANES
	_float_count[side] = int(_float_count[side]) + 1
	var x := (80.0 if boss_side else -380.0) + (36.0 if lane % 2 == 1 else -36.0)
	var y := -200.0 + float(lane) * FLOAT_LANE_HEIGHT
	label.offset_left = x
	label.offset_right = x + 280.0
	label.offset_top = y
	label.offset_bottom = y + 80.0
	_float_layer.add_child(label)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "offset_top", y - 50.0, 0.9)
	tween.tween_property(label, "offset_bottom", y + 30.0, 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.4)
	tween.chain().tween_callback(label.queue_free)
	var same_side: Array[Node] = []
	for child in _float_layer.get_children():
		if not child.is_queued_for_deletion() and str(child.get_meta("side", "")) == side:
			same_side.append(child)
	while same_side.size() > FLOAT_MAX_PER_SIDE:
		same_side.pop_front().queue_free()


func _clear_floats() -> void:
	UiKit.clear(_float_layer)
	_float_count = {"boss": 0, "hero": 0}


## 提交失败（网络/服务器拒绝）：回到就绪，让玩家可以重来。
func show_submit_error(message: String) -> void:
	phase = Phase.READY
	_start_button.visible = true
	_start_button.disabled = false
	_append_feed("end", "结算失败：%s" % BattleReport.escape(message))
	_report.add_line(BattleReport.Kind.LOSE, "结算失败：%s" % message, 0)
	_fx.set_boss_from_art()


## 服务器结算返回后显示结果：完整战报换成服务器的版本，再弹出结算面板。
func show_result(result: Dictionary, name_of: Callable) -> void:
	phase = Phase.RESULT
	var battle: Dictionary = result.get("battle", {}) if typeof(result.get("battle", null)) == TYPE_DICTIONARY else {}
	var lines := BattleReportBuilder.build(battle, _boss_name, BagModel.shown(fight.player_max_hp) if fight != null else 0, BagModel.shown(fight.boss_max_hp) if fight != null else 0, _ult_name)
	BattleReportBuilder.render(_report, lines)
	var view := BattleResultView.build(result, _boss_name, name_of)
	_last_view = view
	_append_feed("end", BattleReport.escape("%s · %s" % [str(view.title), str(view.reason)]))
	UiKit.clear(_result_body)
	var title := UiKit.label(str(view.title), UiTokens.FS_H1, UiTokens.SUCCESS if bool(view.win) else UiTokens.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "ResultTitle"
	title.add_theme_font_override("font", ArtLib.title_font())
	_result_body.add_child(title)
	_result_body.add_child(UiKit.label(str(view.reason), UiTokens.FS_CAPTION, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	_result_body.add_child(UiKit.divider())
	for text in view.lines:
		_result_body.add_child(UiKit.label(str(text), UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	if not (view.loot as Array).is_empty():
		_result_body.add_child(UiKit.label("获得", UiTokens.FS_MICRO, UiTokens.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
		for row in view.loot:
			var color := UiTokens.rarity_color(Catalog.quality_index(str(row.quality))).lightened(0.15)
			var loot_label := UiKit.label(str(row.text), UiTokens.FS_CAPTION, color, HORIZONTAL_ALIGNMENT_CENTER)
			loot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_result_body.add_child(loot_label)
	elif bool(view.win):
		_result_body.add_child(UiKit.label("这次没有掉落", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	for note in view.notes:
		var note_label := UiKit.label(str(note), UiTokens.FS_MICRO, UiTokens.WARNING, HORIZONTAL_ALIGNMENT_CENTER)
		note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_result_body.add_child(note_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_result_body.add_child(spacer)
	var buttons := UiKit.hbox(UiTokens.SP_2)
	var back := UiKit.button("返回", MainTheme.VAR_SECONDARY, UiTokens.H_CTA)
	back.name = "BackButton"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func() -> void: back_requested.emit())
	buttons.add_child(back)
	var again := UiKit.button("再来一次", MainTheme.VAR_PRIMARY, UiTokens.H_CTA)
	again.name = "RetryButton"
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.pressed.connect(func() -> void: retry_requested.emit(stage_slug))
	buttons.add_child(again)
	_result_body.add_child(buttons)
	# 结算内容先准备好；等胜负表现（首领溶解 / 主角变灰 + 横幅，约 1.9 秒）播完再切到结算面板
	if _fx.is_result_playing() and is_visible_in_tree():
		await _fx.result_finished
		if phase != Phase.RESULT:
			return
	_result_panel.visible = true
	_arena.visible = false
	_controls.visible = false


var _last_view: Dictionary = {}


func last_view() -> Dictionary:
	return _last_view


func report_text() -> String:
	return _report.get_parsed_text()
