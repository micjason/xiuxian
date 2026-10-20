class_name HomePage
extends VBoxContainer
## 修炼页（Q 版设计稿 q_cultivate）：莲台场景上打坐的主角（背景图自带莲台）、右侧圆形入口
## 「历练」（副标 = 正在刷的关卡）/「洞府」/「炼丹」（暂未开放）、左下宝箱「+收益」（暂未开放）；
## 下半薄荷底板上：当前一波的关卡卡（进度 3 段、最近一次击杀、最近掉落）和挂机修炼条。
## 「突破」在底栏正中的大圆钮（外壳处理），这里不再放突破按钮。
## 只负责显示和发信号。波次进度由服务器每次心跳给出，两次心跳之间按本地经过的秒数推进（只影响显示）。
## 设计稿坐标（SPEC_Q 第 8 节）按页面区域（画布 y 362 起、x 24 起）换算。

signal breakthrough_requested
signal adventure_requested
signal page_requested(page: String)

const FEED_SECONDS := 9.0
const FEED_MAX := 3
## 页面区左上角在画布上的位置（顶栏 + 刘海 90 之下，页面左右边距 24）——设计稿坐标减去它。
const ORIGIN := Vector2(24, 362)

var _hero: Control
var _ring: TextureRect
var _adventure: Button
var _adventure_caption: Label
var _adventure_dot: Control
var _cave: Button
var _alchemy: Button
var _chest: Button
var _wave_title: Label
var _wave_text: Label
var _wave_bar: QBar
var _feed_label: Label
var _drop_row: HBoxContainer
var _auto_button: Button
var _idle_title: Label
var _idle_text: Label
var _spin: Tween
var _state: Dictionary = {}
var _content: Dictionary = {}
var _elapsed := 0.0
var _feed: Array[Dictionary] = []
var _shown_ratio := -1.0
var _shown_text := ""
var _wave_card: Control


func _init() -> void:
	add_theme_constant_override("separation", 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_hero()
	_build_wave_card()
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gap)
	_build_idle_card()
	var orb_room := Control.new()
	orb_room.name = "OrbRoom"  # 底栏突破球凸出来的那一截
	orb_room.custom_minimum_size = Vector2(0, 150)
	orb_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(orb_room)


func _ready() -> void:
	if _ring != null:
		_spin = create_tween().set_loops()
		_spin.tween_property(_ring, "rotation", TAU, 20.0).from(0.0)


func _sprite(path: String, rect: Rect2, parent: Control, alpha: float = 1.0) -> TextureRect:
	var node := TextureRect.new()
	node.name = path.get_file().to_pascal_case()
	node.texture = ArtLib.q(path) if ArtLib.has_q(path + ".png") else null
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.position = rect.position - ORIGIN
	node.size = rect.size
	node.modulate = Color(1, 1, 1, alpha)
	parent.add_child(node)
	return node


func _build_hero() -> void:
	_hero = Control.new()
	_hero.name = "Hero"
	_hero.custom_minimum_size = Vector2(0, 700)
	_hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hero)
	var hero := QHero.new()
	if not hero.is_animated():
		# 没有动画场景时照旧：光晕 + 慢转虚线环 + 静态拼合图
		_sprite("sprites/fx_aura_radial", Rect2(90, 330, 900, 900), _hero, 0.85)
		_ring = _sprite("sprites/fx_ring_dashed", Rect2(265, 470, 550, 550), _hero, 0.8)
		_ring.pivot_offset = Vector2(275, 275)
	_sprite("sprites/fx_ground_shadow", Rect2(300, 1016, 480, 70), _hero, 0.8)
	# 动画主角（anim_q/hero_meditate）：锚点 = 设计稿 (540, 1070)，角色框 706×690（README 第 1 节）
	hero.name = "HeroSprite"
	hero.position = Vector2(187, 380) - ORIGIN
	hero.size = Vector2(706, 690)
	_hero.add_child(hero)
	_build_side_entries()
	_build_chest()


## 右侧三个圆形入口（设计稿 924,400 / 924,670 / 924,890）。
func _build_side_entries() -> void:
	var adventure := QKit.side_button("tab_adventure", "历练")
	adventure.root.name = "AdventureEntry"
	_adventure = adventure.button
	_adventure.name = "AdventureButton"
	_adventure_dot = adventure.dot
	_adventure.pressed.connect(func() -> void: adventure_requested.emit())
	_place_side(adventure.root, 400)
	_adventure_caption = QKit.outlined("", 30, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 8, HORIZONTAL_ALIGNMENT_CENTER)
	_adventure_caption.name = "AdventureCaption"
	var chip := QKit.tag("", "dark", 30, 14)
	chip.name = "AdventureStage"
	chip.remove_child(chip.get_child(0))
	chip.add_child(_adventure_caption)
	chip.position = Vector2(906, 586) - ORIGIN
	chip.custom_minimum_size = Vector2(168, 44)
	_hero.add_child(chip)
	var cave := QKit.side_button("side_cave", "洞府")
	cave.root.name = "CaveEntry"
	_cave = cave.button
	_cave.name = "CaveButton"
	_cave.pressed.connect(func() -> void: page_requested.emit("cave"))
	_place_side(cave.root, 670)
	var alchemy := QKit.side_button("side_alchemy", "炼丹")
	alchemy.root.name = "AlchemyEntry"
	_alchemy = alchemy.button
	_alchemy.name = "AlchemyButton"
	LockedFeature.wire(_alchemy, "alchemy")
	_place_side(alchemy.root, 890)


func _place_side(root: Control, y: float) -> void:
	root.position = Vector2(924 - 30, y) - ORIGIN
	root.custom_minimum_size = Vector2(192, 190)
	_hero.add_child(root)


## 左下宝箱 + 「+收益」气泡（挂机宝箱玩法还没有：展示，点了提示暂未开放）。
func _build_chest() -> void:
	_sprite("sprites/fx_chest_glow", Rect2(28, 1150, 220, 90), _hero, 0.9)
	_chest = Button.new()
	_chest.name = "ChestButton"
	_chest.focus_mode = Control.FOCUS_NONE
	_chest.flat = true
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		_chest.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_chest.position = Vector2(40, 1040) - ORIGIN
	_chest.size = Vector2(190, 187)
	var art := TextureRect.new()
	art.texture = ArtLib.q("sprites/chest_closed") if ArtLib.has_q("sprites/chest_closed.png") else ArtLib.icon("chest")
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chest.add_child(art)
	LockedFeature.wire(_chest, "idle_chest")
	_hero.add_child(_chest)
	var bubble := QKit.tag("+收益", "orange", 32, 20)
	bubble.name = "ChestBubble"
	bubble.position = Vector2(150, 986) - ORIGIN
	_hero.add_child(bubble)


func _build_wave_card() -> void:
	var card := QKit.panel(UiTokens.Q_CREAM, 34, 30, 22)
	_wave_card = card.panel
	_wave_card.name = "WaveCard"
	_wave_card.custom_minimum_size = Vector2(0, 372)
	_wave_card.size_flags_horizontal = Control.SIZE_FILL
	add_child(_wave_card)
	var body := card.body as VBoxContainer
	body.add_theme_constant_override("separation", 14)
	var head := UiKit.hbox(12)
	body.add_child(head)
	var sword := UiKit.icon("tab_adventure", 64)
	head.add_child(sword)
	_wave_title = QKit.title("", 46, UiTokens.TEXT)
	_wave_title.name = "WaveTitle"
	_wave_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wave_title.clip_text = true
	head.add_child(_wave_title)
	_wave_text = UiKit.label("", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_wave_text.name = "WaveText"
	head.add_child(_wave_text)
	_wave_bar = QKit.bar(0.0, UiTokens.Q_MINT, 40, 3) as QBar
	_wave_bar.name = "WaveBar"
	body.add_child(_wave_bar)
	var row := UiKit.hbox(12)
	body.add_child(row)
	_feed_label = UiKit.label("本波打完后显示击杀与掉落", UiTokens.FS_MICRO, UiTokens.TEXT)
	_feed_label.name = "FeedLine"
	_feed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feed_label.clip_text = true
	row.add_child(_feed_label)
	_auto_button = QKit.button("⚔ 自动挑战中", "m", 60, 30)
	_auto_button.name = "AutoChallenge"
	_auto_button.custom_minimum_size.x = 240
	_auto_button.tooltip_text = "挂机自动刷怪中，点开历练换地点"
	_auto_button.pressed.connect(func() -> void: adventure_requested.emit())
	row.add_child(_auto_button)
	var drops := QKit.inset(UiTokens.Q_CARD, 24, 20, 8)
	drops.panel.name = "DropRow"
	drops.panel.custom_minimum_size = Vector2(0, 104)
	body.add_child(drops.panel)
	_drop_row = UiKit.hbox(14)
	_drop_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	(drops.body as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	(drops.body as VBoxContainer).size_flags_vertical = Control.SIZE_EXPAND_FILL
	drops.body.add_child(_drop_row)
	_render_drops()


func _build_idle_card() -> void:
	var card := PanelContainer.new()
	card.name = "IdleCard"
	card.custom_minimum_size = Vector2(0, 140)
	if ArtLib.qui("panel_pill_132") != null:
		card.add_theme_stylebox_override("panel", QKit.cut_box("panel_pill_132", 20, 6))
		(card.get_theme_stylebox("panel") as StyleBoxTexture).content_margin_left = 16
	else:
		card.add_theme_stylebox_override("panel", QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 4, 66, 8, 20, 6))
	add_child(card)
	var row := UiKit.hbox(UiTokens.SP_2)
	card.add_child(row)
	var disc := QKit.cut_rect("idle_lotus_disc", Vector2(104, 104))
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if disc is TextureRect:
		var lotus := UiKit.icon("res_lotus", 80)
		QKit.center_in(lotus, Vector2(80, 80))
		disc.add_child(lotus)
	row.add_child(disc)
	var text := UiKit.vbox(0)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	_idle_title = QKit.title("挂机修炼中  · · ·", 40, UiTokens.TEXT)
	text.add_child(_idle_title)
	_idle_text = UiKit.label("", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED)
	_idle_text.name = "IdleText"
	text.add_child(_idle_text)


func _process(delta: float) -> void:
	if not visible or _state.is_empty():
		return
	_elapsed += delta
	_refresh_wave_bar()
	_expire_feed(delta)


## 下半薄荷底板的上沿跟着这张卡（外壳交给 Backdrop.set_sheet_anchor）。
func sheet_anchor() -> Control:
	return _wave_card


func adventure_button() -> Button:
	return _adventure


func cave_button() -> Button:
	return _cave


func alchemy_button() -> Button:
	return _alchemy


func chest_button() -> Button:
	return _chest


## 状态变化后重画。next_realm_name 由外壳提供（底栏突破钮用，这里只留接口）。
func bind(state: Dictionary, content: Dictionary, _next_realm_name: String) -> void:
	_state = state
	_content = content
	_elapsed = 0.0
	var caption := WaveView.stage_caption(state)
	_adventure_caption.text = caption if not caption.is_empty() else "未开启"
	var view := BreakthroughView.build(state)
	# 历练入口的红点：突破被首领卡住（修为够了、首领没打）时提醒去历练。
	_adventure_dot.visible = bool(view.has_next) and bool(view.cultivation_ok) and not bool(view.boss_ok)
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
		text += " · 离线最多累计 %s" % OfflineView.duration_text(int(cap))
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
	_wave_bar.segments = maxi(1, int(shown.get("wave_size", 3)))
	_wave_bar.set_ratio(float(shown.ratio))


## 获得修为飘字（float_drop/float_number，README 3a）：本次结算的挂机修为 → 主角头上 (540,720) 蓝色大字，
## 击杀修为 → (780,560) 金色小字。数值就是服务器结算里的 passiveGained / killCultivation（取整），为 0 不飘。
## 只飘修为数字；击杀 / 掉落的文字仍只在下面波次卡片里（v9 去重的要求不变）。
func show_gains(last: Dictionary) -> void:
	if not is_visible_in_tree() or not bool(last.get("online", false)):
		return
	var passive := roundi(float(last.get("passiveGained", 0)))
	var kill := roundi(float(last.get("killCultivation", 0)))
	if passive > 0:
		_float_gain(passive, 0, Vector2(540, 720))
	if kill > 0:
		_float_gain(kill, 1, Vector2(780, 560))


func _float_gain(value: int, style: int, design_pos: Vector2) -> void:
	var node := QFx.make(QFx.FLOAT_NUMBER) as Node2D
	if node == null:
		return
	node.name = "GainFloat"  # 同名兄弟节点会被引擎改名成 @GainFloat@n，所以另外打个 meta 方便查
	node.set_meta(&"gain_float", true)
	node.set("value", value)
	node.set("color_style", style)
	node.set("unit", "修为")
	node.position = design_pos - ORIGIN
	_hero.add_child(node)
	var ap := QFx.player(node)
	ap.animation_finished.connect(func(_name: StringName) -> void: node.queue_free())
	ap.play("pop")


func gain_floats() -> Array[Node]:
	return _hero.get_children().filter(func(n: Node) -> bool: return n.has_meta(&"gain_float") and not n.is_queued_for_deletion())


## 掉落行里第 index 件掉落物格子的画布中心（飞入背包的起点）；没有返回 null。
func drop_slot_centers() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for child in _drop_row.get_children():
		if child is Control and (child as Control).tooltip_text != "":
			out.append((child as Control).get_global_rect().get_center())
	return out


## 击杀 / 掉落反馈：击杀行显示最近一条，掉落行显示最近两件（图标 + 名字）。lines 来自 WaveView.feedback。
func show_feedback(lines: Array[Dictionary]) -> void:
	for line in lines:
		var entry := line.duplicate()
		entry["left"] = FEED_SECONDS
		_feed.append(entry)
		# 不在莲台上飘字：同一条信息已经在下面的波次卡片里显示（负责人 v8 验收意见）
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
	var line_text := ""
	var kind := ""
	for line in _feed:
		if str(line.get("kind", "")) != "drop":
			line_text = str(line.text)
			kind = str(line.kind)
	_feed_label.text = line_text if not line_text.is_empty() else "本波打完后显示击杀与掉落"
	_feed_label.add_theme_color_override("font_color", UiTokens.Q_RED if kind in ["warn", "death"] else UiTokens.TEXT)
	_render_drops()


func _render_drops() -> void:
	UiKit.clear(_drop_row)
	_drop_row.add_child(QKit.title("掉落", 34, UiTokens.TEXT_MUTED))
	var drops: Array[Dictionary] = []
	for line in _feed:
		if str(line.get("kind", "")) == "drop":
			drops.append(line)
	if drops.is_empty():
		_drop_row.add_child(UiKit.label("暂无", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
		return
	for index in range(maxi(0, drops.size() - 2), drops.size()):
		var line := drops[index]
		var view := QKit.reward_view(_content, str(line.get("slug", "")))
		_drop_row.add_child(QKit.reward_slot(_content, str(line.get("slug", "")), 88, int(line.get("quantity", 1))))
		var name := QKit.title(str(view.name), 32, UiTokens.rarity_color(int(view.rarity)).darkened(0.2))
		name.clip_text = true
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_drop_row.add_child(name)
