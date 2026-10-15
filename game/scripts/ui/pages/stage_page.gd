class_name StagePage
extends VBoxContainer
## 历练页（从修炼页「历练」入口进入）：挂机刷怪地点选择、关卡列表（带战力对比）、首领详情（属性、掉落预览）
## 和挑战按钮。点「挑战」进入首领战界面（BattlePage）；战报在首领战界面里，不在这一页。

signal stage_selected(slug: String)
signal challenge_requested(slug: String)
## slug 为空串 = 恢复“自动（当前境界最高关卡）”。
signal idle_stage_requested(slug: String)
signal back_requested

var _state: Dictionary = {}
var _content: Dictionary = {}
var _stages: Array[Dictionary] = []
var selected := ""
var busy := false

var _stage_view: ScrollContainer
var _stage_box: VBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", UiTokens.SP_2)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var top := UiKit.hbox(UiTokens.SP_1)
	var back := UiKit.button("‹ 返回", MainTheme.VAR_GHOST, UiTokens.H_TOUCH)
	back.name = "BackButton"
	back.custom_minimum_size = Vector2(200, UiTokens.H_TOUCH)
	back.pressed.connect(func() -> void: back_requested.emit())
	top.add_child(back)
	var title_box := UiKit.page_title("历练")
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_box)
	var balance := Control.new()
	balance.custom_minimum_size = Vector2(200, 0)
	top.add_child(balance)
	add_child(top)
	_stage_view = ScrollContainer.new()
	_stage_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_stage_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_stage_view)
	_stage_box = UiKit.vbox(UiTokens.SP_2)
	_stage_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_view.add_child(_stage_box)


func bind(state: Dictionary, content: Dictionary, stages: Array[Dictionary], selected_slug: String) -> void:
	_state = state
	_content = content
	_stages = stages
	selected = selected_slug
	_render_stages()


func set_busy(value: bool) -> void:
	busy = value
	_render_stages()


func _render_stages() -> void:
	UiKit.clear(_stage_box)
	var power := int(_state.get("power", 0))
	var head := UiKit.card()
	_stage_box.add_child(head.panel)
	var row := UiKit.hbox(UiTokens.SP_2)
	head.body.add_child(row)
	var realm := UiKit.label(str(_state.get("realmName", "")), UiTokens.FS_H2, UiTokens.TEXT)
	realm.add_theme_font_override("font", ArtLib.title_font())
	realm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(realm)
	row.add_child(UiKit.icon("res_power", 48, UiTokens.GOLD))
	row.add_child(UiKit.label("我的战力 %d" % power, UiTokens.FS_BODY_L, UiTokens.GOLD, HORIZONTAL_ALIGNMENT_RIGHT))
	_stage_box.add_child(_idle_card())
	if _stages.is_empty():
		_stage_box.add_child(UiKit.wrap_label("这个境界还没有可以打的关卡。", UiTokens.FS_BODY, UiTokens.TEXT_MUTED))
		return
	for index in _stages.size():
		_stage_box.add_child(_stage_card(_stages[index], power, index))
	var current := _find(selected)
	if not current.is_empty():
		_stage_box.add_child(_boss_card(current, power))


## 挂机刷怪地点：服务器给出可选关卡（wave.selectable）和当前选择（wave.chosenStageSlug，null = 自动）。
func _idle_card() -> Control:
	var wave: Dictionary = _state.get("wave", {}) if typeof(_state.get("wave", null)) == TYPE_DICTIONARY else {}
	var card := UiKit.card("挂机刷怪地点")
	card.panel.name = "IdleStageCard"
	var chosen := BagModel.plain(wave.get("chosenStageSlug", null))
	var options: Array = wave.get("selectable", [])
	if options.is_empty():
		(card.body as VBoxContainer).add_child(UiKit.wrap_label("这个境界还没有可以刷怪的关卡。", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
		return card.panel
	var auto := UiKit.button("自动（最高关卡）" + ("  ✔" if chosen.is_empty() else ""), MainTheme.VAR_CHOICE_SELECTED if chosen.is_empty() else MainTheme.VAR_CHOICE, 96)
	auto.name = "IdleAuto"
	auto.pressed.connect(func() -> void: idle_stage_requested.emit(""))
	card.body.add_child(auto)
	for option in options:
		if typeof(option) != TYPE_DICTIONARY:
			continue
		var slug := str((option as Dictionary).get("slug", ""))
		var on := slug == chosen
		var text := "%s · %s" % [str((option as Dictionary).get("name", slug)), str((option as Dictionary).get("monsterName", ""))]
		var button := UiKit.button(text + ("  ✔" if on else ""), MainTheme.VAR_CHOICE_SELECTED if on else MainTheme.VAR_CHOICE, 96)
		button.name = "Idle_%s" % slug
		button.disabled = busy
		button.pressed.connect(func() -> void: idle_stage_requested.emit(slug))
		card.body.add_child(button)
	return card.panel


func _find(slug: String) -> Dictionary:
	for stage in _stages:
		if str(stage.get("slug", "")) == slug:
			return stage
	return {}


## 战力对比：用文字+符号表达，不只靠颜色。
static func power_status(mine: int, recommended: int) -> Dictionary:
	if recommended <= 0:
		return {"text": "无推荐战力", "symbol": "－", "level": "none"}
	if mine >= recommended:
		return {"text": "战力足够", "symbol": "✔", "level": "ok"}
	if float(mine) >= float(recommended) * 0.8:
		return {"text": "略低于推荐", "symbol": "!", "level": "warn"}
	return {"text": "战力差距大", "symbol": "✖", "level": "bad"}


func _stage_card(stage: Dictionary, power: int, index: int) -> Control:
	var slug := str(stage.get("slug", ""))
	var chosen := slug == selected
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 224)
	button.focus_mode = Control.FOCUS_NONE
	var frame := ArtLib.nine("row_selected" if chosen else "row_bg")
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, frame if state != "focus" else StyleBoxEmpty.new())
	button.pressed.connect(func() -> void: stage_selected.emit(slug))
	# 关卡配图：水墨山水做底，压暗后文字才看得清。
	var picture := Control.new()
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.offset_left = 10
	picture.offset_top = 10
	picture.offset_right = -10
	picture.offset_bottom = -10
	picture.clip_contents = true
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(picture)
	var art := TextureRect.new()
	art.texture = ArtLib.bg("stage_%d" % (index % 6 + 1))
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.modulate = Color(1, 1, 1, 0.55 if chosen else 0.38)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.add_child(art)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UiTokens.CARD_PADDING)
	button.add_child(margin)
	var row := UiKit.hbox(UiTokens.SP_3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var bosses: Array = stage.get("bosses", [])
	var boss_name := str((bosses[0] as Dictionary).get("name", "")) if not bosses.is_empty() and typeof(bosses[0]) == TYPE_DICTIONARY else "无首领"
	row.add_child(_boss_portrait(boss_name, 148))
	var column := UiKit.vbox(4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	var recommended := int(stage.get("recommendedPower", 0))
	var status := power_status(power, recommended)
	var title := UiKit.label(str(stage.get("displayName", slug)), UiTokens.FS_BODY_L, UiTokens.GOLD_HOVER if chosen else UiTokens.TEXT)
	title.clip_text = true
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 8)
	column.add_child(title)
	var boss_line := UiKit.label("首领：%s" % boss_name, UiTokens.FS_CAPTION, UiTokens.TEXT)
	boss_line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	boss_line.add_theme_constant_override("outline_size", 8)
	column.add_child(boss_line)
	var color := UiTokens.SUCCESS
	match str(status.level):
		"warn":
			color = UiTokens.WARNING
		"bad":
			color = UiTokens.DANGER
		"none":
			color = UiTokens.TEXT_MUTED
	var power_text := "%s %s" % [str(status.symbol), str(status.text)]
	if recommended > 0:
		power_text = "推荐战力 %d    %s" % [recommended, power_text]
	var power_line := UiKit.label(power_text, UiTokens.FS_CAPTION, color)
	power_line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	power_line.add_theme_constant_override("outline_size", 8)
	column.add_child(power_line)
	return button


## 首领头像：剪影图标 + 品质框。
static func _boss_portrait(boss_name: String, size: int) -> Control:
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.add_theme_stylebox_override("panel", ArtLib.nine("slot_r4"))
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = ArtLib.icon(ArtLib.boss_icon_name(boss_name))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = UiTokens.rarity_color(4).lightened(0.2)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(icon)
	return holder


func _boss_card(stage: Dictionary, power: int) -> Control:
	var card := UiKit.card("首领详情")
	var bosses: Array = stage.get("bosses", [])
	var boss: Dictionary = bosses[0] if not bosses.is_empty() and typeof(bosses[0]) == TYPE_DICTIONARY else {}
	var boss_name := str(boss.get("name", "首领"))
	var boss_row := UiKit.hbox(UiTokens.SP_3)
	card.body.add_child(boss_row)
	boss_row.add_child(_boss_portrait(boss_name, 176))
	var boss_info := UiKit.vbox(UiTokens.SP_1)
	boss_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boss_info.alignment = BoxContainer.ALIGNMENT_CENTER
	boss_row.add_child(boss_info)
	var boss_title := UiKit.label(boss_name, UiTokens.FS_H1, UiTokens.TEXT)
	boss_title.add_theme_font_override("font", ArtLib.title_font())
	boss_info.add_child(boss_title)
	var stats := UiKit.hbox(UiTokens.SP_3)
	boss_info.add_child(stats)
	for entry in [["气血", "hp"], ["攻击", "attack"], ["防御", "defense"]]:
		if boss.has(entry[1]):
			stats.add_child(UiKit.label("%s %d" % [entry[0], int(boss[entry[1]])], UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
	card.body.add_child(UiKit.section_title("可能掉落"))
	var defs := {}
	for def in _content.get("items", []):
		if typeof(def) == TYPE_DICTIONARY:
			defs[str((def as Dictionary).get("slug", ""))] = def
	var drops: Array = boss.get("drops", [])
	if drops.is_empty():
		card.body.add_child(UiKit.label("没有掉落", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
	for drop in drops:
		if typeof(drop) != TYPE_DICTIONARY:
			continue
		var slug := str((drop as Dictionary).get("itemSlug", ""))
		var def: Dictionary = defs.get(slug, {})
		var line := UiKit.hbox(UiTokens.SP_2)
		card.body.add_child(line)
		var drop_art := KitStyle.icon_for({"slug": slug, "slot_id": SlotConfig.id_from_server(str(def.get("slot", ""))) if def.get("slot", null) != null else "", "category": BagModel.category_of(def), "kind": str(def.get("kind", ""))})
		line.add_child(UiKit.icon_from(drop_art.get("texture", null) as Texture2D, 56, UiTokens.rarity_color(BagModel.rarity_of(def)).lightened(0.2)))
		var name := UiKit.label(str(def.get("displayName", slug)), UiTokens.FS_CAPTION, UiTokens.rarity_color(BagModel.rarity_of(def)))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name)
		var chance := float((drop as Dictionary).get("chanceBp", 0)) / 100.0
		line.add_child(UiKit.label("%.1f%%" % chance, UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
	var cooldown: Variant = _state.get("challengeCooldownSeconds", null)
	if cooldown != null:
		card.body.add_child(UiKit.label("挑战冷却 %s 秒" % str(cooldown), UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
	var recommended := int(stage.get("recommendedPower", 0))
	var button := UiKit.button("挑战 %s" % boss_name, MainTheme.VAR_PRIMARY, UiTokens.H_CTA + 16)
	button.disabled = busy or boss.is_empty()
	button.pressed.connect(func() -> void: challenge_requested.emit(str(stage.get("slug", ""))))
	card.body.add_child(UiKit.spacer(UiTokens.SP_1))
	card.body.add_child(button)
	if recommended > 0 and power < recommended:
		card.body.add_child(UiKit.wrap_label("我的战力低于推荐值，可能打不过。可以先去角色页换装备。", UiTokens.FS_MICRO, UiTokens.WARNING))
	return card.panel
