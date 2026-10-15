extends Control
## UI 画廊：用真实主题和令牌摆出"尚未在主界面出现"的页面（角色/装备、装备详情、文字战报、组件总览），
## 用于设计评审和截图。所有数据都是示例数据，不连服务器，也不会被正式界面引用。
## 运行：godot --path game res://scenes/dev/ui_gallery.tscn ；截图脚本调用 show_page(名称)。

const PAGES: Array[String] = ["character", "equipment", "battle", "components"]
const APP_THEME: Theme = preload("res://resources/theme/xiuxian_theme.tres")

const SLOT_SAMPLES := [
	{"slot": "兵刃", "name": "青锋剑·试锋", "rarity": 1, "plus": 8},
	{"slot": "道冠", "name": "青锋剑意·冠", "rarity": 2, "plus": 5},
	{"slot": "法袍", "name": "玄龟甲·重岩", "rarity": 3, "plus": 10},
	{"slot": "束带", "name": "天衡·守一带", "rarity": 5, "plus": 12},
	{"slot": "玉佩", "name": "赤焰·焚心佩", "rarity": 4, "plus": 9},
	{"slot": "云履", "name": "", "rarity": -1, "plus": 0},
]

var _page_root: Control


func _ready() -> void:
	theme = APP_THEME
	var backdrop := ColorRect.new()
	backdrop.color = UiTokens.BG_ABYSS
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MainTheme.fill_parent(backdrop)
	add_child(backdrop)
	show_page(PAGES[0])


func show_page(page: String) -> void:
	if _page_root != null:
		_page_root.queue_free()
	_page_root = Control.new()
	MainTheme.fill_parent(_page_root)
	add_child(_page_root)
	var inset := UiSafeArea.current(get_viewport())
	_header(inset)
	var margin := MarginContainer.new()
	MainTheme.fill_parent(margin)
	margin.offset_left = UiTokens.PAGE_MARGIN + inset.x
	margin.offset_right = -(UiTokens.PAGE_MARGIN + inset.z)
	margin.offset_top = inset.y + UiTokens.H_HEADER + UiTokens.SP_2
	margin.offset_bottom = -(UiTokens.H_TAB + inset.w + UiTokens.SP_2)
	_page_root.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", UiTokens.SP_2)
	margin.add_child(content)
	match page:
		"character":
			_build_character(content)
		"equipment":
			_build_equipment(content)
		"battle":
			_build_battle(content)
		_:
			_build_components(content)
	_tab_bar(inset, "行囊" if page in ["character", "equipment"] else "历练")


# ---------- 页面骨架 ----------

func _header(inset: Vector4) -> void:
	var brand := _label("修仙", MainTheme.VAR_TITLE)
	brand.add_theme_font_size_override("font_size", UiTokens.FS_H1)
	brand.set_anchors_preset(Control.PRESET_TOP_LEFT)
	brand.offset_left = UiTokens.PAGE_MARGIN + inset.x + UiTokens.SP_2
	brand.offset_top = inset.y + UiTokens.SP_2
	_page_root.add_child(brand)
	var power := _label("战力 1024", &"")
	power.add_theme_stylebox_override("normal", MainTheme.cultivation_capsule())
	power.add_theme_color_override("font_color", UiTokens.GOLD)
	power.add_theme_font_size_override("font_size", UiTokens.FS_BODY_L)
	power.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	power.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	power.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	power.offset_left = -(UiTokens.PAGE_MARGIN + inset.z + 440.0)
	power.offset_right = -(UiTokens.PAGE_MARGIN + inset.z)
	power.offset_top = inset.y + UiTokens.SP_2
	power.offset_bottom = inset.y + UiTokens.SP_2 + UiTokens.H_HEADER - UiTokens.SP_3
	_page_root.add_child(power)


func _tab_bar(inset: Vector4, active: String) -> void:
	var dock := Panel.new()
	dock.add_theme_stylebox_override("panel", MainTheme.tab_dock())
	dock.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dock.offset_top = -(UiTokens.H_TAB + inset.w)
	_page_root.add_child(dock)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_top = -(UiTokens.H_TAB + inset.w)
	row.offset_bottom = -inset.w
	_page_root.add_child(row)
	for name in ["修炼", "历练", "行囊", "功法"]:
		var tab := _button(name, MainTheme.VAR_TAB_ACTIVE if name == active else MainTheme.VAR_TAB)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0, UiTokens.H_TAB)
		row.add_child(tab)


func _card(parent: Control, fill_height: bool = false) -> VBoxContainer:
	var card := PanelContainer.new()
	if fill_height:
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, UiTokens.CARD_PADDING)
	card.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTokens.SP_2)
	pad.add_child(box)
	return box


# ---------- 角色与装备 ----------

func _build_character(content: VBoxContainer) -> void:
	var box := _card(content, true)
	var title := _label("角色 · 示例数据", MainTheme.VAR_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var realm := _label("炼气中期", &"")
	realm.add_theme_font_size_override("font_size", UiTokens.FS_HUGE)
	realm.add_theme_color_override("font_color", UiTokens.JADE)
	realm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(realm)
	var stats := GridContainer.new()
	stats.columns = 4
	stats.add_theme_constant_override("h_separation", UiTokens.SP_1)
	for pair in [["攻击", "104"], ["防御", "96"], ["气血", "3300"], ["速度", "21"]]:
		stats.add_child(_stat_cell(pair[0], pair[1]))
	box.add_child(stats)
	box.add_child(HSeparator.new())
	box.add_child(_label("装备（6 个核心槽）", MainTheme.VAR_ACCENT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", UiTokens.SP_2)
	grid.add_theme_constant_override("v_separation", UiTokens.SP_2)
	for sample in SLOT_SAMPLES:
		grid.add_child(_slot_cell(sample))
	box.add_child(grid)
	box.add_child(_label("法宝、灵宠为第三期内容，先预留位置。", MainTheme.VAR_CAPTION))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", UiTokens.SP_2)
	var auto := _button("一键换装", MainTheme.VAR_PRIMARY)
	auto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto.custom_minimum_size = Vector2(0, UiTokens.H_CTA)
	var enhance := _button("一键强化", MainTheme.VAR_SECONDARY)
	enhance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enhance.custom_minimum_size = Vector2(0, UiTokens.H_CTA)
	actions.add_child(auto)
	actions.add_child(enhance)
	box.add_child(actions)


func _stat_cell(caption: String, value: String) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = MainTheme.VAR_INNER_PANEL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)
	var cap := _label(caption, MainTheme.VAR_CAPTION)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)
	var number := _label(value, &"")
	number.add_theme_font_size_override("font_size", UiTokens.FS_BODY_L)
	number.add_theme_color_override("font_color", UiTokens.GOLD)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(number)
	return panel


func _slot_cell(sample: Dictionary) -> Control:
	var rarity := int(sample["rarity"])
	var empty := rarity < 0
	var border := UiTokens.BORDER_SUBTLE if empty else UiTokens.rarity_color(rarity)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 232)
	var style := MainTheme.inner_panel()
	style.border_color = border
	style.set_border_width_all(2 if empty else 4)
	style.content_margin_left = UiTokens.SP_2
	style.content_margin_right = UiTokens.SP_2
	panel.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", UiTokens.SP_1)
	panel.add_child(col)
	var slot := _label(str(sample["slot"]), MainTheme.VAR_CAPTION)
	slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(slot)
	var name := _label("未装备" if empty else str(sample["name"]), &"")
	name.add_theme_font_size_override("font_size", UiTokens.FS_CAPTION)
	name.add_theme_color_override("font_color", UiTokens.TEXT_MUTED if empty else border)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(name)
	if not empty:
		var tag := _label("%s  +%d" % [UiTokens.RARITY_NAMES[rarity], int(sample["plus"])], MainTheme.VAR_CAPTION)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(tag)
	return panel


func _build_equipment(content: VBoxContainer) -> void:
	var list := _card(content)
	list.add_child(_label("行囊 · 示例数据", MainTheme.VAR_TITLE))
	var names := ["素木冠", "云纹道袍", "玄龟甲·重岩"]
	for i in names.size():
		var row := _button(names[i], MainTheme.VAR_CHOICE_SELECTED if i == 2 else MainTheme.VAR_CHOICE)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(0, UiTokens.H_TOUCH)
		list.add_child(row)
	# 详情卡叠在列表上方，模拟点开一件装备
	var scrim := ColorRect.new()
	scrim.color = UiTokens.SCRIM
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MainTheme.fill_parent(scrim)
	_page_root.add_child(scrim)
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -480
	card.offset_right = 480
	card.offset_top = -700
	card.offset_bottom = 640
	var panel_style := MainTheme.hero_panel()
	panel_style.border_color = UiTokens.rarity_color(3)
	panel_style.set_border_width_all(4)
	card.add_theme_stylebox_override("panel", panel_style)
	_page_root.add_child(card)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, UiTokens.SP_4)
	card.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTokens.SP_2)
	pad.add_child(box)
	var name := _label("玄龟甲·重岩", &"")
	name.add_theme_font_size_override("font_size", UiTokens.FS_H1)
	name.add_theme_color_override("font_color", UiTokens.rarity_color(3))
	box.add_child(name)
	box.add_child(_label("珍品 · 法袍 · 3 阶 · +10", MainTheme.VAR_SUBTLE))
	box.add_child(HSeparator.new())
	box.add_child(_label("防御 128　　气血 690", &""))
	box.add_child(_label("随机词条", MainTheme.VAR_ACCENT))
	for line in ["防御 ＋4.9%", "生命 ＋5.2%", "闪避评级 ＋31"]:
		var affix := _label("◆ " + line, &"")
		affix.add_theme_font_size_override("font_size", UiTokens.FS_BODY)
		box.add_child(affix)
	box.add_child(_label("词条评分 30 · 生存向 81", MainTheme.VAR_SUBTLE))
	var set_title := _label("套装 玄龟磐石（2/4）", MainTheme.VAR_ACCENT)
	box.add_child(set_title)
	var set_on := _label("▲ 2 件：防御 ＋6%", MainTheme.VAR_SUCCESS_LABEL)
	box.add_child(set_on)
	var set_off := _label("　 4 件：受到伤害 －5%（未激活）", MainTheme.VAR_CAPTION)
	box.add_child(set_off)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var compare := _label("对比身上：防御 ＋12　生命 ＋88", MainTheme.VAR_SUCCESS_LABEL)
	box.add_child(compare)
	var equip := _button("穿戴", MainTheme.VAR_PRIMARY)
	equip.custom_minimum_size = Vector2(0, UiTokens.H_CTA)
	box.add_child(equip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTokens.SP_2)
	var upgrade := _button("强化", MainTheme.VAR_SECONDARY)
	var decompose := _button("分解", MainTheme.VAR_DANGER)
	for button in [upgrade, decompose]:
		(button as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(button as Button).custom_minimum_size = Vector2(0, UiTokens.H_TOUCH)
		row.add_child(button)
	box.add_child(row)


# ---------- 文字战报 ----------

func _build_battle(content: VBoxContainer) -> void:
	var box := _card(content, true)
	var boss_name := _label("寒潭蛟 · 水", &"")
	boss_name.add_theme_font_size_override("font_size", UiTokens.FS_H2)
	boss_name.add_theme_color_override("font_color", UiTokens.ELEMENT_WATER)
	box.add_child(boss_name)
	box.add_child(_label("推荐战力 1500 · 示例数据", MainTheme.VAR_SUBTLE))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, UiTokens.H_BAR)
	bar.value = 38
	box.add_child(bar)
	var report_panel := PanelContainer.new()
	report_panel.theme_type_variation = MainTheme.VAR_INNER_PANEL
	report_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(report_panel)
	var report := BattleReport.new()
	report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report_panel.add_child(report)
	report.add_round(1)
	report.add_line(BattleReport.Kind.DAMAGE_DEALT, "你 使出「青云剑诀」击中 寒潭蛟", 412)
	report.add_line(BattleReport.Kind.DAMAGE_TAKEN, "寒潭蛟 的尾击打中 你", 268)
	report.add_line(BattleReport.Kind.BUFF, "你 获得【养气诀】：攻击 ＋10%（3 回合）")
	report.add_round(2)
	report.add_line(BattleReport.Kind.CRIT, "你 的「青云剑诀」击中 寒潭蛟", 1096)
	report.add_line(BattleReport.Kind.DEBUFF, "寒潭蛟 陷入【冰封】，下回合无法行动")
	report.add_line(BattleReport.Kind.MISS, "寒潭蛟 的水箭未命中 你")
	report.add_round(3)
	report.add_line(BattleReport.Kind.HEAL, "你 运转「回春诀」恢复气血", 320)
	report.add_line(BattleReport.Kind.DAMAGE_DEALT, "你 的普通攻击击中 寒潭蛟", 388)
	report.add_line(BattleReport.Kind.PLAIN, "寒潭蛟 气血只剩 38%，开始狂暴。")
	report.add_result(true, "胜利！用时 4 回合")
	var loot := _label("获得：云纹道袍（精品）、聚气丹 ×2", MainTheme.VAR_ACCENT)
	loot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(loot)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", UiTokens.SP_2)
	var again := _button("再战一次", MainTheme.VAR_PRIMARY)
	var back := _button("返回", MainTheme.VAR_SECONDARY)
	for button in [again, back]:
		(button as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(button as Button).custom_minimum_size = Vector2(0, UiTokens.H_CTA)
		actions.add_child(button)
	box.add_child(actions)


# ---------- 组件总览 ----------

func _build_components(content: VBoxContainer) -> void:
	var box := _card(content, true)
	box.add_child(_label("组件总览", MainTheme.VAR_TITLE))
	box.add_child(_label("按钮：主 / 次 / 危险 / 禁用", MainTheme.VAR_CAPTION))
	var primary := _button("主按钮：突破境界", MainTheme.VAR_PRIMARY)
	primary.custom_minimum_size = Vector2(0, UiTokens.H_CTA)
	box.add_child(primary)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTokens.SP_2)
	var secondary := _button("次要", MainTheme.VAR_SECONDARY)
	var danger := _button("分解", MainTheme.VAR_DANGER)
	var disabled := _button("禁用", MainTheme.VAR_SECONDARY)
	disabled.disabled = true
	for button in [secondary, danger, disabled]:
		(button as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(button as Button).custom_minimum_size = Vector2(0, UiTokens.H_TOUCH)
		row.add_child(button)
	box.add_child(row)
	box.add_child(_label("输入框", MainTheme.VAR_CAPTION))
	var edit := LineEdit.new()
	edit.placeholder_text = "用户名"
	edit.custom_minimum_size = Vector2(0, UiTokens.H_TOUCH)
	box.add_child(edit)
	box.add_child(_label("进度条与语义文字", MainTheme.VAR_CAPTION))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, UiTokens.H_BAR)
	bar.value = 66
	box.add_child(bar)
	var semantic := HBoxContainer.new()
	semantic.add_theme_constant_override("separation", UiTokens.SP_3)
	semantic.add_child(_label("成功", MainTheme.VAR_SUCCESS_LABEL))
	semantic.add_child(_label("失败", MainTheme.VAR_DANGER_LABEL))
	semantic.add_child(_label("提示", MainTheme.VAR_SUBTLE))
	box.add_child(semantic)
	box.add_child(_label("装备稀有度：凡 良 精 珍 绝 仙", MainTheme.VAR_CAPTION))
	var rarity_row := HBoxContainer.new()
	rarity_row.add_theme_constant_override("separation", UiTokens.SP_2)
	for i in UiTokens.RARITY_NAMES.size():
		var chip := _label(UiTokens.RARITY_NAMES[i], &"")
		chip.add_theme_font_size_override("font_size", UiTokens.FS_CAPTION)
		chip.add_theme_color_override("font_color", UiTokens.rarity_color(i))
		var chip_style := MainTheme.inner_panel()
		chip_style.border_color = UiTokens.rarity_color(i)
		chip_style.set_border_width_all(2)
		chip.add_theme_stylebox_override("normal", chip_style)
		rarity_row.add_child(chip)
	box.add_child(rarity_row)
	box.add_child(_label("五行点缀：金 木 水 火 土", MainTheme.VAR_CAPTION))
	var elements := HBoxContainer.new()
	elements.add_theme_constant_override("separation", UiTokens.SP_3)
	var element_names := ["金", "木", "水", "火", "土"]
	var element_colors := [UiTokens.ELEMENT_METAL, UiTokens.ELEMENT_WOOD, UiTokens.ELEMENT_WATER, UiTokens.ELEMENT_FIRE, UiTokens.ELEMENT_EARTH]
	for i in element_names.size():
		var element := _label(element_names[i], &"")
		element.add_theme_font_size_override("font_size", UiTokens.FS_H2)
		element.add_theme_color_override("font_color", element_colors[i])
		elements.add_child(element)
	box.add_child(elements)
	var toast := _label("已保存。", &"")
	toast.add_theme_stylebox_override("normal", MainTheme.cultivation_capsule())
	toast.add_theme_color_override("font_color", UiTokens.SUCCESS)
	toast.add_theme_font_size_override("font_size", UiTokens.FS_BODY)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(toast)
	var dialog := PanelContainer.new()
	box.add_child(dialog)
	var dbox := VBoxContainer.new()
	dialog.add_child(dbox)
	var dtitle := _label("发现新版本", MainTheme.VAR_TITLE)
	dtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dbox.add_child(dtitle)
	var dbody := _label("新版本 0.6.8：优化修炼结算，修复若干问题。", &"")
	dbody.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dbody.add_theme_font_size_override("font_size", UiTokens.FS_BODY)
	dbox.add_child(dbody)


# ---------- 小工具 ----------

func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	if variation != &"":
		label.theme_type_variation = variation
	return label


func _button(text: String, variation: StringName) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	return button
