class_name HomePage
extends VBoxContainer
## 修炼页（确认稿 03）：莲台场景 + 简洁波次进度；移除右侧入口与挂机说明。
## 左下宝箱、光晕、气泡只在离线报告待领取时出现。
## 「突破」在底栏正中的大圆钮（外壳处理），这里不再放突破按钮。
## 只负责显示和发信号。波次进度由服务器每次心跳给出，两次心跳之间按本地经过的秒数推进（只影响显示）。
## 设计稿坐标（SPEC_Q 第 8 节）按页面区域（画布 y 362 起、x 24 起）换算。

signal breakthrough_requested
signal adventure_requested
signal page_requested(page: String)
## 有未领取的离线收益报告时，点左下宝箱再打开离线弹窗（点空白关掉后的再领入口）。
signal offline_requested

const FEED_SECONDS := 9.0
const FEED_MAX := 3
## 页面区左上角在画布上的位置（顶栏 + 刘海 90 之下，页面左右边距 24）——设计稿坐标减去它。
const ORIGIN := Vector2(24, 362)

var _hero: Control
var _ring: TextureRect
var _adventure: Button
var _skill: Button
var _alchemy: Button
var _chest_glow: Control
var _chest: Button
var _chest_dot: Control
var _chest_bubble: PanelContainer
var _chest_bubble_label: Label
var _offline_pending := false
var _wave_title: Label
var _wave_text: Label
var _wave_bar: QBar
var _feed_label: Label
var _drop_row: HBoxContainer
var _auto_button: Button
var _spin: Tween
var _state: Dictionary = {}
var _content: Dictionary = {}
var _elapsed := 0.0
var _feed: Array[Dictionary] = []
var _shown_ratio := -1.0
var _shown_text := ""
var _wave_card: Control
var _last_feed_text := ""

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

	var orb_room := Control.new()
	orb_room.name = "OrbRoom"  # 底栏突破球凸出来的那一截
	orb_room.custom_minimum_size = Vector2(0, 180)
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
	_sprite("sprites/fx_ground_shadow", Rect2(300, 1236, 480, 70), _hero, 0.8)
	# 确认稿人物居中落在莲台前沿；换装贴图仍完全由服务器 appearance 决定。
	hero.name = "HeroSprite"
	hero.position = Vector2(130, 490) - ORIGIN
	hero.size = Vector2(820, 800)
	_hero.add_child(hero)
	_build_chest()


## 左下宝箱 + 「+收益」气泡。
## 只在有未领取离线报告时显示，领取后图标、光晕、气泡一起消失。
func _build_chest() -> void:
	_chest_glow = _sprite("sprites/fx_chest_glow", Rect2(28, 1150, 220, 90), _hero, 0.9)
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
	_chest_dot = QKit.reddot(38)
	_chest_dot.name = "OfflineDot"
	_chest_dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_chest_dot.offset_left = -48
	_chest_dot.offset_right = -10
	_chest_dot.offset_top = 8
	_chest_dot.offset_bottom = 46
	_chest_dot.visible = false
	_chest.add_child(_chest_dot)
	_chest.pressed.connect(_on_chest_pressed)
	_hero.add_child(_chest)
	_chest_bubble = QKit.tag("+收益", "orange", 32, 20)
	_chest_bubble.name = "ChestBubble"
	_chest_bubble.position = Vector2(150, 986) - ORIGIN
	_chest_bubble_label = _chest_bubble.get_child(0) as Label
	_hero.add_child(_chest_bubble)
	set_offline_pending(false)

func _on_chest_pressed() -> void:
	if _offline_pending:
		offline_requested.emit()



## 外壳在有/无 pending offlineReport 时调用：控制宝箱红点与气泡文案。
func set_offline_pending(pending: bool) -> void:
	_offline_pending = pending
	if _chest != null:
		_chest.visible = pending
	if _chest_glow != null:
		_chest_glow.visible = pending
	if _chest_bubble != null:
		_chest_bubble.visible = pending
	if _chest_dot != null:
		_chest_dot.visible = pending
	if _chest_bubble_label != null:
		_chest_bubble_label.text = "待领取" if pending else "+收益"
	if _chest != null:
		_chest.tooltip_text = "领取离线收益" if pending else ""

func _build_wave_card() -> void:
	var card := QKit.panel(UiTokens.Q_CREAM, 34, 30, 22)
	_wave_card = card.panel
	_wave_card.name = "WaveCard"
	_wave_card.custom_minimum_size = Vector2(0, 280)
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

	_wave_bar = QKit.bar(0.0, UiTokens.Q_MINT, 40, 3) as QBar
	_wave_bar.name = "WaveBar"
	body.add_child(_wave_bar)
	var row := UiKit.hbox(12)
	body.add_child(row)
	_feed_label = UiKit.label("挂机战斗中…", UiTokens.FS_MICRO, UiTokens.TEXT)
	_feed_label.name = "FeedLine"
	_feed_label.visible = false
	_feed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feed_label.clip_text = true
	row.add_child(_feed_label)
	_wave_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wave_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_wave_text)
	_auto_button = QKit.button("⚔ 自动挑战中", "m", 60, 30)
	_auto_button.name = "AutoChallenge"
	_auto_button.custom_minimum_size.x = 240
	_auto_button.tooltip_text = "挂机自动刷怪中，点开历练换地点"
	_auto_button.pressed.connect(func() -> void: adventure_requested.emit())
	row.add_child(_auto_button)
	var drops := QKit.inset(UiTokens.Q_CARD, 24, 20, 8)
	drops.panel.name = "DropRow"
	drops.panel.visible = false
	drops.panel.custom_minimum_size = Vector2(0, 104)
	body.add_child(drops.panel)
	_drop_row = UiKit.hbox(14)
	_drop_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	(drops.body as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	(drops.body as VBoxContainer).size_flags_vertical = Control.SIZE_EXPAND_FILL
	drops.body.add_child(_drop_row)
	_render_drops()

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

func skill_button() -> Button:
	return _skill

func alchemy_button() -> Button:
	return _alchemy

func chest_button() -> Button:
	return _chest


## 状态变化后重画。next_realm_name 由外壳提供（底栏突破钮用，这里只留接口）。
func bind(state: Dictionary, content: Dictionary, _next_realm_name: String) -> void:
	_state = state
	_content = content
	var meditate := _hero.get_node_or_null("HeroSprite") as QHero
	if meditate != null:
		meditate.apply_outfit(OutfitAppearance.texture(state.get("appearance", null), "meditate"))
	_elapsed = 0.0
	var report: Variant = state.get("offlineReport", null)
	set_offline_pending(typeof(report) == TYPE_DICTIONARY and not (report as Dictionary).is_empty())
	_shown_ratio = -1.0
	_refresh_wave_bar()

func _refresh_wave_bar() -> void:
	var online := true
	var last: Variant = _state.get("lastSettle", null)
	if typeof(last) == TYPE_DICTIONARY and last.has("online"):
		online = bool((last as Dictionary).get("online", true)) or int((last as Dictionary).get("seconds", 0)) == 0
	var shown := WaveView.display(_state, _elapsed if online else 0.0)
	var wave: Dictionary = _state.get("wave", {}) if typeof(_state.get("wave", null)) == TYPE_DICTIONARY else {}
	_wave_title.text = str(wave.get("stageName", "")) if bool(shown.available) else "未开启"
	var text := "%d/%d" % [int(shown.kills), int(shown.wave_size)] if bool(shown.available) else "—"
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
	if not _drop_row.is_visible_in_tree():
		return out
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
	# 有真实击杀/阵亡就记住；过期后仍显示最后一句，避免和开发占位句轮切（FINDINGS #17）。
	if not line_text.is_empty():
		_last_feed_text = line_text
	_feed_label.text = line_text if not line_text.is_empty() else (_last_feed_text if not _last_feed_text.is_empty() else "挂机战斗中…")
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
		_drop_row.add_child(UiKit.label("等待掉落", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
		return
	for index in range(maxi(0, drops.size() - 2), drops.size()):
		var line := drops[index]
		var view := QKit.reward_view(_content, str(line.get("slug", "")))
		_drop_row.add_child(QKit.reward_slot(_content, str(line.get("slug", "")), 88, int(line.get("quantity", 1))))
		var name := QKit.title(str(view.name), 32, UiTokens.rarity_color(int(view.rarity)).darkened(0.2))
		name.clip_text = true
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_drop_row.add_child(name)
