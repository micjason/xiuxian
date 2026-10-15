class_name SkillPage
extends VBoxContainer
## 功法页（设计稿 02，原型阶段只展示，不升级、不消耗资源）：
## 「我的功法」三张卡（名称、修炼加成、状态）+ 选中功法的详情 + 三本功法的离线收益对比。
## 点卡片只切换下方详情，不发任何服务器请求。

var _view: Dictionary = {}
var _selected := ""
var _list: VBoxContainer
var _detail: VBoxContainer
var _count: Label
var _hint: Label


func _init() -> void:
	add_theme_constant_override("separation", UiTokens.SP_1)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(UiKit.page_title("功法"))
	var head := UiKit.hbox(UiTokens.SP_2)
	head.add_child(UiKit.label("我的功法", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
	_count = UiKit.label("", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_count)
	add_child(head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var column := UiKit.vbox(UiTokens.SP_2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	_list = UiKit.vbox(UiTokens.SP_1)
	column.add_child(_list)
	_detail = UiKit.vbox(UiTokens.SP_1)
	column.add_child(_detail)
	_hint = UiKit.label("", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_hint)


func bind(state: Dictionary, content: Dictionary) -> void:
	_view = SkillView.build(state, content)
	if _selected.is_empty() or not _has(_selected):
		_selected = str((_view.selected as Dictionary).get("slug", ""))
	_render()


func view() -> Dictionary:
	return _view


func selected_slug() -> String:
	return _selected


func select(slug: String) -> void:
	if _has(slug):
		_selected = slug
		_render()


func _has(slug: String) -> bool:
	for card in _view.get("cards", []):
		if str(card.slug) == slug:
			return true
	return false


func _render() -> void:
	UiKit.clear(_list)
	UiKit.clear(_detail)
	var cards: Array = _view.get("cards", [])
	_count.text = "已习得 %d / %d  ·  同一时间只生效 1 本" % [int(_view.get("learned_count", 0)), int(_view.get("total_count", 0))]
	if cards.is_empty():
		_list.add_child(UiKit.wrap_label("后台还没有配置带修炼加成的功法。", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
		return
	for card in cards:
		_list.add_child(_card(card))
	_render_detail()
	_hint.text = "原型阶段：功法只做展示，不升级、不消耗资源"


func _card(card: Dictionary) -> Control:
	var status := str(card.status)
	var locked := status == "locked"
	var chosen := str(card.slug) == _selected
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 150)
	button.focus_mode = Control.FOCUS_NONE
	var frame := ArtLib.nine("row_selected" if chosen else "row_bg")
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, frame if state != "focus" else StyleBoxEmpty.new())
	button.pressed.connect(select.bind(str(card.slug)))
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UiTokens.SP_2)
	button.add_child(margin)
	var row := UiKit.hbox(UiTokens.SP_2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var icon_frame := PanelContainer.new()
	icon_frame.custom_minimum_size = Vector2(112, 112)
	icon_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_frame.add_theme_stylebox_override("panel", ArtLib.nine("slot_empty" if locked else "slot_r3"))
	icon_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_frame.add_child(UiKit.icon("cat_scroll", 72, UiTokens.TEXT_DISABLED if locked else UiTokens.rarity_color(3).lightened(0.25)))
	row.add_child(icon_frame)
	var info := UiKit.vbox(0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	var title := UiKit.label("《%s》" % str(card.name), UiTokens.FS_H2, UiTokens.TEXT_DISABLED if locked else UiTokens.GOLD_HOVER)
	title.add_theme_font_override("font", ArtLib.title_font())
	title.clip_text = true
	info.add_child(title)
	info.add_child(UiKit.label(str(card.bonus_text), UiTokens.FS_CAPTION, UiTokens.TEXT_DISABLED if locked else UiTokens.SUCCESS))
	var chip := PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override("panel", ArtLib.nine("chip"))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip_color := UiTokens.GOLD if status == "running" else (UiTokens.TEXT if status == "learned" else UiTokens.TEXT_DISABLED)
	chip.add_child(UiKit.label(str(card.status_text), UiTokens.FS_MICRO, chip_color, HORIZONTAL_ALIGNMENT_CENTER))
	row.add_child(chip)
	return button


func _render_detail() -> void:
	var picked: Dictionary = {}
	for card in _view.cards:
		if str(card.slug) == _selected:
			picked = card
	if picked.is_empty():
		return
	var panel := UiKit.card()
	panel.panel.name = "DetailCard"
	_detail.add_child(panel.panel)
	var body := panel.body as VBoxContainer
	var head := UiKit.hbox(UiTokens.SP_2)
	body.add_child(head)
	var title := UiKit.label("《%s》" % str(picked.name), UiTokens.FS_H1, UiTokens.GOLD_HOVER)
	title.add_theme_font_override("font", ArtLib.title_font())
	head.add_child(title)
	head.add_child(UiKit.label(str(picked.status_text), UiTokens.FS_CAPTION, UiTokens.GOLD if str(picked.status) == "running" else UiTokens.TEXT_MUTED))
	var base := float(_view.get("base_per_second", 0))
	var bonus := float(picked.bonus_bp) / 10000.0
	body.add_child(UiKit.wrap_label("修炼期间每秒修为提升 %s%%，离线收益同样生效。" % SkillView._pct(float(picked.bonus_bp)), UiTokens.FS_CAPTION, UiTokens.TEXT))
	var stats := UiKit.hbox(UiTokens.SP_2)
	body.add_child(stats)
	stats.add_child(_stat_box("修炼加成", "修为 +%s%%" % SkillView._pct(float(picked.bonus_bp))))
	stats.add_child(_stat_box("每秒基础修为", "%s → %s" % [HomePage._plain_number(base), HomePage._plain_number(base * (1.0 + bonus))]))
	var cap_hours := int(float(_view.get("cap_seconds", 28800)) / 3600.0)
	body.add_child(UiKit.section_title("%d 本功法对比（离线 %d 小时）" % [(_view.comparison as Array).size(), cap_hours]))
	for row in _view.comparison:
		body.add_child(_compare_row(row, cap_hours))


func _stat_box(caption: String, value: String) -> Control:
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_stylebox_override("panel", ArtLib.nine("chip"))
	var column := UiKit.vbox(0)
	box.add_child(column)
	column.add_child(UiKit.label(caption, UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	column.add_child(UiKit.label(value, UiTokens.FS_CAPTION, UiTokens.GOLD_HOVER))
	return box


func _compare_row(row: Dictionary, cap_hours: int) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ArtLib.nine("row_selected" if bool(row.selected) else "row_bg"))
	var line := UiKit.hbox(UiTokens.SP_1)
	panel.add_child(line)
	var locked := str(row.status) == "locked"
	var name := UiKit.label("《%s》" % str(row.name), UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED if locked else UiTokens.TEXT)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	line.add_child(name)
	line.add_child(UiKit.label(str(row.bonus_text), UiTokens.FS_MICRO, UiTokens.SUCCESS))
	line.add_child(UiKit.label("%d小时 %s" % [cap_hours, OfflineView.grouped(float(row.total))], UiTokens.FS_CAPTION, UiTokens.GOLD_HOVER if not locked else UiTokens.TEXT_DISABLED, HORIZONTAL_ALIGNMENT_RIGHT))
	return panel
