class_name HomePage
extends VBoxContainer
## 修炼页（首页，按设计稿 01）：莲台人物、右侧「历练」入口、当前一波的进度与击杀/掉落反馈、
## 「突破」金色大按钮（修为条只在顶栏显示一次）、挂机收益卡片。
## 只负责显示和发信号：突破流程、历练、跳页都交给外壳处理。
## 波次进度由服务器每次心跳给出，两次心跳之间按本地经过的秒数推进（只影响显示）。

signal breakthrough_requested
signal adventure_requested
signal page_requested(page: String)

const FEED_SECONDS := 9.0
const FEED_MAX := 3

var _hero: Control
var _ring: TextureRect
var _adventure: Button
var _adventure_caption: Label
var _adventure_dot: Control
var _wave_title: Label
var _wave_text: Label
var _wave_bar_host: Control
var _wave_bar: Control
var _feed_box: VBoxContainer
var _cta: Button
var _cta_dot: Control
var _idle_title: Label
var _idle_text: Label
var _spin: Tween
var _state: Dictionary = {}
var _elapsed := 0.0
var _feed: Array[Dictionary] = []
var _shown_ratio := -1.0
var _shown_text := ""


func _init() -> void:
	add_theme_constant_override("separation", UiTokens.SP_2)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_hero()
	_build_wave_card()
	_build_cta()
	_build_idle_card()


func _ready() -> void:
	_spin = create_tween().set_loops()
	_spin.tween_property(_ring, "rotation", TAU, 90.0).from(0.0)


func _build_hero() -> void:
	_hero = Control.new()
	_hero.name = "Hero"
	_hero.custom_minimum_size = Vector2(0, 420)
	_hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hero)
	var glow := TextureRect.new()
	glow.texture = ArtLib.ui("glow_soft")
	glow.set_anchors_preset(Control.PRESET_CENTER)
	glow.offset_left = -330
	glow.offset_right = 330
	glow.offset_top = -330
	glow.offset_bottom = 330
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.modulate = Color(UiTokens.GOLD, 0.28)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.add_child(glow)
	_ring = TextureRect.new()
	_ring.texture = ArtLib.ui("formation")
	_ring.set_anchors_preset(Control.PRESET_CENTER)
	_ring.offset_left = -290
	_ring.offset_right = 290
	_ring.offset_top = -290
	_ring.offset_bottom = 290
	_ring.pivot_offset = Vector2(290, 290)
	_ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ring.modulate = Color(1, 1, 1, 0.9)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.add_child(_ring)
	var avatar := UiKit.icon("avatar_meditate", 250, UiTokens.GOLD_HOVER)
	avatar.set_anchors_preset(Control.PRESET_CENTER)
	avatar.offset_left = -125
	avatar.offset_right = 125
	avatar.offset_top = -150
	avatar.offset_bottom = 100
	_hero.add_child(avatar)
	_hero.add_child(_build_adventure_entry())


## 右侧「历练」入口：圆形按钮（复用剑图标 tab_adventure）+ 红点 + 标牌 + 关卡副文字。
func _build_adventure_entry() -> Control:
	var holder := VBoxContainer.new()
	holder.name = "AdventureEntry"
	holder.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	holder.offset_left = -190
	holder.offset_right = 0
	holder.offset_top = -10
	holder.offset_bottom = 190
	holder.add_theme_constant_override("separation", 6)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_adventure = Button.new()
	_adventure.name = "AdventureButton"
	_adventure.custom_minimum_size = Vector2(150, 150)
	_adventure.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_adventure.focus_mode = Control.FOCUS_NONE
	var disc := KitStyle.box(Color(0.1, 0.27, 0.22, 0.95), UiTokens.GOLD, 5, 999)
	for state in ["normal", "hover", "disabled", "focus"]:
		_adventure.add_theme_stylebox_override(state, disc if state != "focus" else StyleBoxEmpty.new())
	_adventure.add_theme_stylebox_override("pressed", KitStyle.box(Color(0.14, 0.34, 0.28, 0.98), UiTokens.GOLD_HOVER, 5, 999))
	var sword := UiKit.icon("tab_adventure", 96, UiTokens.GOLD_HOVER)
	sword.set_anchors_preset(Control.PRESET_CENTER)
	sword.offset_left = -48
	sword.offset_right = 48
	sword.offset_top = -48
	sword.offset_bottom = 48
	_adventure.add_child(sword)
	_adventure_dot = UiKit.reddot()
	_adventure_dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_adventure_dot.offset_left = -38
	_adventure_dot.offset_right = -2
	_adventure_dot.offset_top = 2
	_adventure_dot.offset_bottom = 38
	_adventure.add_child(_adventure_dot)
	_adventure.pressed.connect(func() -> void: adventure_requested.emit())
	holder.add_child(_adventure)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", ArtLib.nine("chip"))
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(UiKit.label("历练", UiTokens.FS_CAPTION, UiTokens.GOLD_HOVER, HORIZONTAL_ALIGNMENT_CENTER))
	holder.add_child(plate)
	_adventure_caption = UiKit.label("", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_adventure_caption.clip_text = true
	holder.add_child(_adventure_caption)
	return holder


func _build_wave_card() -> void:
	var card := UiKit.card()
	card.panel.name = "WaveCard"
	add_child(card.panel)
	var body := card.body as VBoxContainer
	var head := UiKit.hbox(UiTokens.SP_2)
	body.add_child(head)
	_wave_title = UiKit.label("", UiTokens.FS_BODY, UiTokens.GOLD)
	_wave_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wave_title.clip_text = true
	head.add_child(_wave_title)
	_wave_text = UiKit.label("", UiTokens.FS_CAPTION, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	head.add_child(_wave_text)
	_wave_bar_host = Control.new()
	_wave_bar_host.custom_minimum_size = Vector2(0, 44)
	_wave_bar_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_wave_bar_host)
	_feed_box = UiKit.vbox(2)
	_feed_box.name = "Feed"
	body.add_child(_feed_box)


func _build_cta() -> void:
	_cta = UiKit.cta_button("突破", "突破至 —", MainTheme.VAR_PRIMARY, 168)
	_cta.name = "BreakthroughButton"
	_cta.pressed.connect(func() -> void: breakthrough_requested.emit())
	_cta_dot = UiKit.reddot()
	_cta_dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_cta_dot.offset_left = -50
	_cta_dot.offset_right = -14
	_cta_dot.offset_top = 10
	_cta_dot.offset_bottom = 46
	_cta_dot.visible = false
	_cta.add_child(_cta_dot)
	add_child(_cta)


func _build_idle_card() -> void:
	var card := PanelContainer.new()
	card.name = "IdleCard"
	card.add_theme_stylebox_override("panel", ArtLib.nine("panel_card"))
	add_child(card)
	var row := UiKit.hbox(UiTokens.SP_2)
	card.add_child(row)
	row.add_child(UiKit.icon("res_cultivation", 64, UiTokens.JADE))
	var text := UiKit.vbox(0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	_idle_title = UiKit.label("挂机修炼中", UiTokens.FS_BODY, UiTokens.TEXT)
	text.add_child(_idle_title)
	_idle_text = UiKit.label("", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED)
	text.add_child(_idle_text)


func _process(delta: float) -> void:
	if not visible or _state.is_empty():
		return
	_elapsed += delta
	_refresh_wave_bar()
	_expire_feed(delta)


## 供外壳读：突破入口按钮。
func breakthrough_button() -> Button:
	return _cta


func adventure_button() -> Button:
	return _adventure


## 状态变化后重画。next_realm_name 由外壳提供。
func bind(state: Dictionary, content: Dictionary, next_realm_name: String) -> void:
	_state = state
	_elapsed = 0.0
	var view := BreakthroughView.build(state, next_realm_name)
	if view.has_next:
		UiKit.set_cta(_cta, "突破", "突破至 %s" % next_realm_name)
		_cta.disabled = false
	else:
		UiKit.set_cta(_cta, "已圆满", "当前已是最高境界")
		_cta.disabled = true
	_cta_dot.visible = view.can_start
	_adventure_caption.text = WaveView.stage_caption(state)
	_adventure_dot.visible = true
	_shown_ratio = -1.0
	_refresh_wave_bar()
	_render_idle(state, content)


func _render_idle(state: Dictionary, content: Dictionary) -> void:
	var rate: Dictionary = state.get("cultivationRate", {}) if typeof(state.get("cultivationRate", null)) == TYPE_DICTIONARY else {}
	var gain := float(rate.get("gainPerTick", 0))
	var bonus := float(rate.get("bonusBp", 0)) / 10000.0
	var tick := 1.0
	for realm in content.get("realms", []):
		if typeof(realm) == TYPE_DICTIONARY and str((realm as Dictionary).get("slug", "")) == str(state.get("realmSlug", "")):
			tick = maxf(float((realm as Dictionary).get("tickSeconds", 1.0)), 0.1)
	var globals: Dictionary = content.get("globals", {}) if typeof(content.get("globals", null)) == TYPE_DICTIONARY else {}
	var cap := float(globals.get("offlineCapSeconds", 0))
	if gain <= 0.0:
		_idle_text.text = "后台还没设置修炼速度，现在得不到修为。"
		return
	var per_second := gain * (1.0 + bonus) / tick
	var text := "每秒修为 +%s" % _plain_number(per_second)
	if cap > 0.0:
		text += "    离线最多累计 %s" % OfflineView.duration_text(int(cap))
	_idle_text.text = text


static func _plain_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return ("%.2f" % value).trim_suffix("0")


func _refresh_wave_bar() -> void:
	var online := true
	var last: Variant = _state.get("lastSettle", null)
	if typeof(last) == TYPE_DICTIONARY and last.has("online"):
		online = bool((last as Dictionary).get("online", true)) or int((last as Dictionary).get("seconds", 0)) == 0
	var shown := WaveView.display(_state, _elapsed if online else 0.0)
	var wave: Dictionary = _state.get("wave", {}) if typeof(_state.get("wave", null)) == TYPE_DICTIONARY else {}
	_wave_title.text = str(wave.get("stageName", "")) if bool(shown.available) else "未开启"
	var text := str(shown.text)
	if text == _shown_text and absf(float(shown.ratio) - _shown_ratio) < 0.004:
		return
	_shown_text = text
	_shown_ratio = float(shown.ratio)
	_wave_text.text = text
	UiKit.clear(_wave_bar_host)
	_wave_bar = UiKit.ratio_bar(float(shown.ratio), "bar_fill_jade", 44)
	_wave_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wave_bar_host.add_child(_wave_bar)


## 击杀 / 掉落反馈：卡片里留最近几条，英雄区飘字。lines 来自 WaveView.feedback。
func show_feedback(lines: Array[Dictionary]) -> void:
	for line in lines:
		_feed.append({"text": str(line.get("text", "")), "kind": str(line.get("kind", "")), "quality": str(line.get("quality", "")), "left": FEED_SECONDS})
		# 不再在莲台上飘字：同一条信息已经在下面的波次卡片里显示，两处重复（负责人 v8 验收意见）
	while _feed.size() > FEED_MAX:
		_feed.pop_front()
	_render_feed()


func feed_texts() -> Array[String]:
	var out: Array[String] = []
	for line in _feed:
		out.append(str(line.text))
	return out


func _expire_feed(delta: float) -> void:
	if _feed.is_empty():
		return
	var changed := false
	for line in _feed:
		line["left"] = float(line.left) - delta
	while not _feed.is_empty() and float(_feed[0].left) <= 0.0:
		_feed.pop_front()
		changed = true
	if changed:
		_render_feed()


func _render_feed() -> void:
	UiKit.clear(_feed_box)
	for line in _feed:
		var label := UiKit.label(str(line.text), UiTokens.FS_MICRO, _feed_color(str(line.kind), str(line.quality)))
		label.clip_text = true
		_feed_box.add_child(label)


static func _feed_color(kind: String, quality: String) -> Color:
	match kind:
		"kill":
			return UiTokens.JADE
		"warn", "death":
			return UiTokens.WARNING
		"drop":
			return UiTokens.rarity_color({"white": 0, "green": 1, "blue": 2, "purple": 3, "orange": 4, "red": 5}.get(quality, 1) as int).lightened(0.15)
	return UiTokens.TEXT
