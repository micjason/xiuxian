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
## 最近一个还没解锁的关卡（带锁图标显示）：{stage, realm, boss, monster, power}；没有就是空字典。
var _locked_stage: Dictionary = {}
## 当前境界之上最近一个有首领的关卡：{stage, boss, realm, power}。没有首领可打时用它说明“哪个境界解锁哪个首领”。
var _locked_next: Dictionary = {}
var selected := ""
var busy := false
var _focus_detail := false

var _stage_view: ScrollContainer
var _stage_box: VBoxContainer
## 「挑战」按钮固定在页面底部（紧贴标签栏上方，页面容器已经扣掉了安全区），首领详情在它上面滚动。
var _challenge_bar: VBoxContainer
var _challenge_button: Button


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
	_challenge_bar = UiKit.vbox(0)
	_challenge_bar.name = "ChallengeBar"
	_challenge_bar.visible = false
	add_child(_challenge_bar)


## stages = 当前境界已解锁的全部关卡（有首领的和只刷怪的）；locked_stage = 下一个未解锁关卡；
## locked_boss = 之上最近的首领关（见 _locked_next）。
func bind(state: Dictionary, content: Dictionary, stages: Array[Dictionary], selected_slug: String, locked_boss: Dictionary = {}, locked_stage: Dictionary = {}) -> void:
	_state = state
	_content = content
	_stages = stages
	_locked_next = locked_boss
	_locked_stage = locked_stage
	selected = selected_slug
	_render_stages()


func set_busy(value: bool) -> void:
	busy = value
	_render_stages()


func _render_stages() -> void:
	# 心跳每次都会重绘：保持滚动位置；玩家刚点了某个关卡就滚到下面的详情。
	var keep_scroll := _stage_view.scroll_vertical
	var focus_detail := _focus_detail
	_focus_detail = false
	_restore_scroll.call_deferred(keep_scroll, focus_detail)
	UiKit.clear(_stage_box)
	UiKit.clear(_challenge_bar)
	_challenge_button = null
	_challenge_bar.visible = false
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
	for index in _stages.size():
		_stage_box.add_child(_stage_card(_stages[index], power, index))
	if not _locked_stage.is_empty():
		_stage_box.add_child(_locked_card(_locked_stage))
	var current := _find(selected)
	if not current.is_empty():
		if _has_boss(current):
			_stage_box.add_child(_boss_card(current, power))
		else:
			_stage_box.add_child(_monster_card(current))
	elif _stages.is_empty():
		var empty := UiKit.card("关卡")
		empty.panel.name = "StageDetailCard"
		empty.body.add_child(UiKit.wrap_label("这个境界还没有开放的关卡。", UiTokens.FS_BODY, UiTokens.TEXT_MUTED))
		_stage_box.add_child(empty.panel)


## 功法书在内容里按功法 slug 配（skills），查不到物品定义时用功法名。
func _skill_name(slug: String) -> String:
	for row in _content.get("skills", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == slug:
			return str((row as Dictionary).get("displayName", slug))
	return slug


func _restore_scroll(value: int, focus_detail: bool) -> void:
	await get_tree().process_frame
	if not is_instance_valid(_stage_view):
		return
	var detail := _stage_box.find_child("StageDetailCard", false, false) as Control
	if focus_detail and detail != null:
		_stage_view.scroll_vertical = maxi(0, int(detail.position.y) - 24)
	else:
		_stage_view.scroll_vertical = value


static func _has_boss(stage: Dictionary) -> bool:
	return not (stage.get("bosses", []) as Array).is_empty()


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


## 当前境界没有首领可挑战时的说明。注意上面“挂机刷怪地点”里列的是普通关卡（只刷怪、没有首领），
## 两者不矛盾：首领关要到更高的境界才解锁。
static func empty_text(realm_name: String, locked_next: Dictionary) -> String:
	var head := "%s还没有首领可以挑战。" % realm_name if not realm_name.is_empty() else "当前境界还没有首领可以挑战。"
	if locked_next.is_empty():
		return head + "上面「挂机刷怪地点」里的关卡只刷小怪，修炼页会自动刷。"
	var text := head + "突破到「%s」后解锁「%s」的首领「%s」" % [str(locked_next.get("realm", "更高境界")), str(locked_next.get("stage", "")), str(locked_next.get("boss", ""))]
	if int(locked_next.get("power", 0)) > 0:
		text += "（推荐战力 %d）" % int(locked_next.get("power", 0))
	return text + "。现在可以先在上面的「挂机刷怪地点」刷怪积累修为。"


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
	button.pressed.connect(func() -> void:
		_focus_detail = true
		stage_selected.emit(slug))
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
	var has_boss := _has_boss(stage)
	var title_name := _boss_name(stage) if has_boss else _monster_name(stage)
	row.add_child(_boss_portrait(title_name, 148))
	var column := UiKit.vbox(4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	var recommended := int(stage.get("recommendedPower", 0))
	var title := UiKit.label(str(stage.get("displayName", slug)), UiTokens.FS_BODY_L, UiTokens.GOLD_HOVER if chosen else UiTokens.TEXT)
	title.clip_text = true
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 8)
	column.add_child(title)
	# 没有首领的关卡不显示“首领”行，只写怪物（真实数据：原型里首领只在每个大境界的第三层）。
	var line_text := "首领：%s" % title_name if has_boss else "怪物：%s · 无首领" % title_name
	var boss_line := UiKit.label(line_text, UiTokens.FS_CAPTION, UiTokens.TEXT)
	boss_line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	boss_line.add_theme_constant_override("outline_size", 8)
	column.add_child(boss_line)
	var color := UiTokens.SUCCESS
	var power_text := "可挂机刷怪"
	if has_boss:
		var status := power_status(power, recommended)
		match str(status.level):
			"warn":
				color = UiTokens.WARNING
			"bad":
				color = UiTokens.DANGER
			"none":
				color = UiTokens.TEXT_MUTED
		power_text = "%s %s" % [str(status.symbol), str(status.text)]
		if recommended > 0:
			power_text = "推荐战力 %d    %s" % [recommended, power_text]
	else:
		color = UiTokens.TEXT_MUTED
	var power_line := UiKit.label(power_text, UiTokens.FS_CAPTION, color)
	power_line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	power_line.add_theme_constant_override("outline_size", 8)
	column.add_child(power_line)
	var tag := _tag_text(stage, has_boss, chosen)
	if not tag.is_empty():
		var chip := PanelContainer.new()
		chip.name = "Tag"
		chip.add_theme_stylebox_override("panel", ArtLib.nine("chip"))
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		chip.offset_right = -22
		chip.offset_top = 22
		chip.add_child(UiKit.label(tag, UiTokens.FS_MICRO, UiTokens.GOLD_HOVER, HORIZONTAL_ALIGNMENT_CENTER))
		button.add_child(chip)
	return button


## 卡片右上角的小标签：真实状态才显示（已通关只来自服务器的突破关卡 cleared），不编造。
func _tag_text(stage: Dictionary, has_boss: bool, chosen: bool) -> String:
	var gate: Variant = (_state.get("breakthrough", {}) as Dictionary).get("requiredStage", null) if typeof(_state.get("breakthrough", null)) == TYPE_DICTIONARY else null
	if has_boss and typeof(gate) == TYPE_DICTIONARY and str((gate as Dictionary).get("slug", "")) == str(stage.get("slug", "")) and bool((gate as Dictionary).get("cleared", false)):
		return "已通关"
	if chosen:
		return "当前挑战" if has_boss else "当前查看"
	return ""


static func _boss_name(stage: Dictionary) -> String:
	var bosses: Array = stage.get("bosses", [])
	return str((bosses[0] as Dictionary).get("name", "")) if not bosses.is_empty() and typeof(bosses[0]) == TYPE_DICTIONARY else ""


static func _monster_name(stage: Dictionary) -> String:
	var monsters: Array = stage.get("monsters", [])
	return str((monsters[0] as Dictionary).get("name", "")) if not monsters.is_empty() and typeof(monsters[0]) == TYPE_DICTIONARY else "怪物"


## 下一个还没解锁的关卡：灰色卡片 + 锁图标 + 解锁条件（不可点）。
func _locked_card(info: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.name = "LockedStageCard"
	panel.add_theme_stylebox_override("panel", ArtLib.nine("row_bg", Color(1, 1, 1, 0.55)))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UiKit.hbox(UiTokens.SP_2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	row.add_child(UiKit.icon("ui_lock", 64, UiTokens.TEXT_MUTED))
	var column := UiKit.vbox(2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	column.add_child(UiKit.label(str(info.get("stage", "")), UiTokens.FS_BODY_L, UiTokens.TEXT_MUTED))
	var what := "首领：%s" % str(info.get("boss", "")) if not str(info.get("boss", "")).is_empty() else "怪物：%s" % str(info.get("monster", ""))
	column.add_child(UiKit.label("%s · %s解锁" % [what, str(info.get("realm", "更高境界"))], UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
	return panel


## 选中的关卡没有首领：显示怪物数据和掉落概率，并说明首领在哪个境界解锁（没有挑战按钮）。
func _monster_card(stage: Dictionary) -> Control:
	var card := UiKit.card("关卡详情")
	card.panel.name = "StageDetailCard"
	var monsters: Array = stage.get("monsters", [])
	var monster: Dictionary = monsters[0] if not monsters.is_empty() and typeof(monsters[0]) == TYPE_DICTIONARY else {}
	var row := UiKit.hbox(UiTokens.SP_3)
	card.body.add_child(row)
	row.add_child(_boss_portrait(_monster_name(stage), 176))
	var info := UiKit.vbox(UiTokens.SP_1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info)
	var name := UiKit.label(_monster_name(stage), UiTokens.FS_H1, UiTokens.TEXT)
	name.add_theme_font_override("font", ArtLib.title_font())
	info.add_child(name)
	var stats := UiKit.hbox(UiTokens.SP_3)
	info.add_child(stats)
	for entry in [["气血", "hp"], ["攻击", "attack"], ["防御", "defense"]]:
		if monster.has(entry[1]):
			stats.add_child(UiKit.label("%s %d" % [entry[0], int(monster[entry[1]])], UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
	if monster.has("killCultivation"):
		card.body.add_child(UiKit.label("每只怪物击败后修为 +%d" % int(monster.get("killCultivation", 0)), UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
	var drop: Variant = stage.get("monsterDrop", null)
	if typeof(drop) == TYPE_DICTIONARY and (drop as Dictionary).has("chanceBp"):
		card.body.add_child(UiKit.label("每只怪物掉落装备概率 %.1f%%" % (float((drop as Dictionary).get("chanceBp", 0)) / 100.0), UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
	var hint := UiKit.wrap_label(empty_text(str(_state.get("realmName", "")), _locked_next), UiTokens.FS_CAPTION, UiTokens.WARNING)
	hint.name = "NoBossHint"
	card.body.add_child(hint)
	return card.panel


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
	card.panel.name = "StageDetailCard"
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
	var rows: Array[Dictionary] = []
	for drop in drops:
		if typeof(drop) == TYPE_DICTIONARY:
			rows.append({"slug": str((drop as Dictionary).get("itemSlug", "")), "chance": float((drop as Dictionary).get("chanceBp", 0)) / 100.0})
	# 服务器的首领掉落写在 repeat（重复挑战：装备 + 额外物品）和 firstClear（首通奖励）里。
	var repeat: Variant = boss.get("repeat", null)
	if typeof(repeat) == TYPE_DICTIONARY:
		if bool((repeat as Dictionary).get("gear", false)):
			rows.append({"text": "装备（随境界品质）", "chance": -1.0})
		for extra in (repeat as Dictionary).get("extras", []):
			if typeof(extra) == TYPE_DICTIONARY:
				var qty := "" if int((extra as Dictionary).get("maxQty", 1)) <= 1 else " ×%d~%d" % [int((extra as Dictionary).get("minQty", 1)), int((extra as Dictionary).get("maxQty", 1))]
				rows.append({"slug": str((extra as Dictionary).get("itemSlug", "")), "suffix": qty, "chance": float((extra as Dictionary).get("chanceBp", 0)) / 100.0})
	if rows.is_empty():
		card.body.add_child(UiKit.label("没有掉落", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
	for entry in rows:
		var slug := str(entry.get("slug", ""))
		var def: Dictionary = defs.get(slug, {})
		var line := UiKit.hbox(UiTokens.SP_2)
		card.body.add_child(line)
		var label_text := str(entry.get("text", ""))
		var label_color := UiTokens.TEXT
		if not slug.is_empty():
			var drop_art := KitStyle.icon_for({"slug": slug, "slot_id": SlotConfig.id_from_server(str(def.get("slot", ""))) if def.get("slot", null) != null else "", "category": BagModel.category_of(def), "kind": str(def.get("kind", ""))})
			line.add_child(UiKit.icon_from(drop_art.get("texture", null) as Texture2D, 56, UiTokens.rarity_color(BagModel.rarity_of(def)).lightened(0.2)))
			label_text = str(def.get("displayName", slug)) + str(entry.get("suffix", ""))
			label_color = UiTokens.rarity_color(BagModel.rarity_of(def))
		var name := UiKit.label(label_text, UiTokens.FS_CAPTION, label_color)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name)
		if float(entry.get("chance", -1.0)) >= 0.0:
			line.add_child(UiKit.label("%.1f%%" % float(entry.get("chance", 0.0)), UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
	var first_clear: Array = boss.get("firstClear", [])
	if not first_clear.is_empty():
		var parts: Array[String] = []
		for reward in first_clear:
			if typeof(reward) != TYPE_DICTIONARY:
				continue
			if str((reward as Dictionary).get("kind", "")) == "cultivation":
				parts.append("修为 +%d" % int((reward as Dictionary).get("amount", 0)))
			else:
				var reward_slug := str((reward as Dictionary).get("itemSlug", ""))
				var item_def: Dictionary = defs.get(reward_slug, {})
				parts.append("%s ×%d" % [str(item_def.get("displayName", _skill_name(reward_slug))), int((reward as Dictionary).get("quantity", 1))])
		if not parts.is_empty():
			card.body.add_child(UiKit.wrap_label("首通奖励：" + "、".join(parts), UiTokens.FS_CAPTION, UiTokens.GOLD))
	var cooldown: Variant = _state.get("challengeCooldownSeconds", null)
	if cooldown != null:
		card.body.add_child(UiKit.label("挑战冷却 %s 秒" % str(cooldown), UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
	var recommended := int(stage.get("recommendedPower", 0))
	if recommended > 0 and power < recommended:
		card.body.add_child(UiKit.wrap_label("我的战力低于推荐值，可能打不过。可以先去角色页换装备。", UiTokens.FS_MICRO, UiTokens.WARNING))
	_challenge_button = UiKit.button("挑战 %s" % boss_name, MainTheme.VAR_PRIMARY, UiTokens.H_CTA + 16)
	_challenge_button.name = "StageChallengeButton"
	_challenge_button.disabled = busy or boss.is_empty()
	_challenge_button.pressed.connect(func() -> void: challenge_requested.emit(str(stage.get("slug", ""))))
	_challenge_bar.add_child(_challenge_button)
	_challenge_bar.visible = true
	return card.panel


## 供测试：固定在底部的挑战按钮（没选中关卡时为 null）。
func challenge_button() -> Button:
	return _challenge_button
