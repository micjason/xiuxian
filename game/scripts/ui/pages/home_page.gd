class_name HomePage
extends ScrollContainer
## 修炼页（首页）：阵法 + 境界、修为进度、突破大按钮、挂机收益、下一步建议。
## 只负责显示和发信号：突破、跳转页面、选关卡都交给外壳处理。

signal breakthrough_requested
signal page_requested(page: String)
signal stage_requested(slug: String)

var _root: VBoxContainer
var _ring: TextureRect
var _realm: Label
var _chance: Label
var _cult_value: Label
var _bar_host: VBoxContainer
var _breakthrough: Button
var _hint: Label
var _banner: Label
var _extras: VBoxContainer
var _spin: Tween


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root = UiKit.vbox(UiTokens.SP_3)
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_root)
	_build_hero()
	_extras = UiKit.vbox(UiTokens.SP_2)
	_root.add_child(_extras)


func _build_hero() -> void:
	var hero := Control.new()
	hero.custom_minimum_size = Vector2(0, 640)
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(hero)
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
	hero.add_child(glow)
	_ring = TextureRect.new()
	_ring.texture = ArtLib.ui("formation")
	_ring.set_anchors_preset(Control.PRESET_CENTER)
	_ring.offset_left = -300
	_ring.offset_right = 300
	_ring.offset_top = -300
	_ring.offset_bottom = 300
	_ring.pivot_offset = Vector2(300, 300)
	_ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ring.modulate = Color(1, 1, 1, 0.9)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(_ring)
	var avatar := UiKit.icon("avatar_meditate", 250, UiTokens.GOLD_HOVER)
	avatar.set_anchors_preset(Control.PRESET_CENTER)
	avatar.offset_left = -125
	avatar.offset_right = 125
	avatar.offset_top = -170
	avatar.offset_bottom = 80
	hero.add_child(avatar)
	_realm = UiKit.label("—", UiTokens.FS_HUGE, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_realm.add_theme_font_override("font", ArtLib.title_font())
	_realm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_realm.add_theme_constant_override("outline_size", 14)
	_realm.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_realm.offset_top = -190
	_realm.offset_bottom = -90
	hero.add_child(_realm)
	_chance = UiKit.label("", UiTokens.FS_CAPTION, UiTokens.JADE, HORIZONTAL_ALIGNMENT_CENTER)
	_chance.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_chance.offset_top = -86
	_chance.offset_bottom = -20
	_chance.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_chance.add_theme_constant_override("outline_size", 8)
	hero.add_child(_chance)

	var card := UiKit.card()
	_root.add_child(card.panel)
	var body := card.body as VBoxContainer
	var row := UiKit.hbox(UiTokens.SP_2)
	body.add_child(row)
	row.add_child(UiKit.icon("res_cultivation", 52, UiTokens.JADE))
	_cult_value = UiKit.label("", UiTokens.FS_BODY_L, UiTokens.TEXT)
	_cult_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_cult_value)
	_bar_host = UiKit.vbox(0)
	body.add_child(_bar_host)
	_hint = UiKit.wrap_label("", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_hint)
	_breakthrough = UiKit.button("突破境界", MainTheme.VAR_PRIMARY, UiTokens.H_CTA + 16)
	_breakthrough.pressed.connect(func() -> void: breakthrough_requested.emit())
	body.add_child(_breakthrough)
	_banner = UiKit.wrap_label("", UiTokens.FS_BODY, UiTokens.GOLD)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	body.add_child(_banner)


func _ready() -> void:
	_spin = create_tween().set_loops()
	_spin.tween_property(_ring, "rotation", TAU, 90.0).from(0.0)


## 供外壳读：突破按钮。
func breakthrough_button() -> Button:
	return _breakthrough


func show_banner(text: String, good: bool) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", UiTokens.GOLD if good else UiTokens.DANGER)
	_banner.visible = not text.is_empty()


func set_busy(value: bool) -> void:
	_breakthrough.disabled = value or _breakthrough.disabled


## 状态变化后重画。realm_name_of(slug) 由外壳提供；suggestions 是 {stage, upgrades, enhanceable}。
func bind(state: Dictionary, content: Dictionary, next_realm_name: String, suggestions: Dictionary, busy: bool) -> void:
	var breakthrough: Dictionary = state.get("breakthrough", {})
	var cultivation := float(state.get("cultivation", 0))
	var cost := float(breakthrough.get("cost", 0))
	var next_slug := str(breakthrough.get("nextSlug", ""))
	var gain := float((state.get("cultivationRate", {}) as Dictionary).get("gainPerTick", 0))
	_realm.text = str(state.get("realmName", ""))
	_chance.text = "" if next_slug.is_empty() else "突破成功率 %d%%" % int(round(float(breakthrough.get("rateBp", 0)) / 100.0))
	UiKit.clear(_bar_host)
	var ratio := 0.0
	if gain <= 0.0:
		_cult_value.text = "修为 %s" % CultivationFormat.amount(cultivation)
		_hint.text = "后台还没设置修炼速度，现在得不到修为。"
		_breakthrough.disabled = true
		_breakthrough.text = "突破境界"
	elif next_slug.is_empty():
		_cult_value.text = "修为 %s" % CultivationFormat.amount(cultivation)
		_hint.text = "已至当前最高境界"
		_breakthrough.disabled = true
		_breakthrough.text = "已圆满"
		ratio = 1.0
	else:
		var can_break := cultivation >= cost
		_cult_value.text = "修为 %s / %s" % [CultivationFormat.amount(cultivation), CultivationFormat.amount(cost)]
		_hint.text = "修为已足，可尝试突破「%s」" % next_realm_name if can_break else "距离「%s」还差 %s" % [next_realm_name, CultivationFormat.amount(cost - cultivation)]
		_breakthrough.disabled = not can_break or busy
		_breakthrough.text = "突破境界"
		ratio = clampf(cultivation / maxf(cost, 1.0), 0.0, 1.0)
	_bar_host.add_child(UiKit.ratio_bar(ratio, "bar_fill_gold" if ratio >= 1.0 else "bar_fill_jade", 52))
	_render_extras(state, content, gain, suggestions)


func _render_extras(state: Dictionary, content: Dictionary, gain: float, suggestions: Dictionary) -> void:
	UiKit.clear(_extras)
	var income := UiKit.card("挂机收益")
	_extras.add_child(income.panel)
	if gain <= 0:
		income.body.add_child(UiKit.wrap_label("后台还没设置修炼速度，现在得不到修为。", UiTokens.FS_CAPTION, UiTokens.WARNING))
	else:
		var row := UiKit.hbox(UiTokens.SP_2)
		income.body.add_child(row)
		row.add_child(UiKit.icon("res_cultivation", 48, UiTokens.JADE))
		row.add_child(UiKit.label("每秒 %s · 每小时约 %s" % [CultivationFormat.amount(gain), CultivationFormat.amount(gain * 3600.0)], UiTokens.FS_BODY, UiTokens.TEXT))
	var globals: Dictionary = content.get("globals", {}) if typeof(content.get("globals", {})) == TYPE_DICTIONARY else {}
	var cap := float(globals.get("offlineCapSeconds", 0))
	if cap > 0:
		income.body.add_child(UiKit.label("离线最多累计 %s 小时" % ("%.1f" % (cap / 3600.0)).trim_suffix(".0"), UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
	var next := UiKit.card("下一步")
	_extras.add_child(next.panel)
	var stage: Dictionary = suggestions.get("stage", {})
	if not stage.is_empty():
		var recommended := int(stage.get("recommendedPower", 0))
		var text := "挑战 %s" % str(stage.get("displayName", ""))
		if recommended > 0:
			text += "（推荐战力 %d）" % recommended
		var go_stage := UiKit.button(text, MainTheme.VAR_SECONDARY)
		go_stage.pressed.connect(func() -> void: stage_requested.emit(str(stage.get("slug", ""))))
		next.body.add_child(go_stage)
	var upgrades := int(suggestions.get("upgrades", 0))
	if upgrades > 0:
		var go_gear := UiKit.button("行囊里有 %d 件比身上更强的装备，去换装" % upgrades, MainTheme.VAR_SECONDARY)
		go_gear.pressed.connect(func() -> void: page_requested.emit("character"))
		next.body.add_child(go_gear)
	var enhanceable := int(suggestions.get("enhanceable", 0))
	if enhanceable > 0:
		var go_enhance := UiKit.button("有 %d 件身上的装备可以强化或突破" % enhanceable, MainTheme.VAR_JADE)
		go_enhance.pressed.connect(func() -> void: page_requested.emit("character"))
		next.body.add_child(go_enhance)
	if stage.is_empty() and upgrades == 0 and enhanceable == 0:
		next.body.add_child(UiKit.label("暂时没有建议，继续修炼吧。", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
