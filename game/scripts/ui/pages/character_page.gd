class_name CharacterPage
extends ScrollContainer
## 角色页：角色头部（境界、战力）+ 装备栏（纸娃娃）+ 属性 + 战力构成。
## 装备栏按 SlotConfig 生成：6 个核心部位 + 法宝/灵宠占位。点部位：有装备→详情；空→挑选可替换的装备。
## 法宝/灵宠是预留位（第三期开放）。

## kind: equip / unequip / use / enhance / enhance_max / breakthrough / decompose；ids: 物品 id 数组。
signal action_requested(kind: String, ids: Array)

var popup: GamePopup
var flags: ItemFlags
var model: BagModel = BagModel.new()

var _state: Dictionary = {}
var _content: Dictionary = {}
var _root: VBoxContainer
var _cells: Dictionary = {}


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root = UiKit.vbox(UiTokens.SP_3)
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_root)


func bind(state: Dictionary, content: Dictionary, item_flags: ItemFlags) -> void:
	_state = state
	_content = content
	flags = item_flags
	refresh()


func refresh() -> void:
	model = BagModel.from_state(_state, _content, {})
	UiKit.clear(_root)
	_cells.clear()
	var slots := EquipModel.slots_of(model)
	_build_header()
	_build_paper_doll(slots)
	_build_attributes(slots)
	_build_power()


func _build_header() -> void:
	var card := UiKit.card()
	_root.add_child(card.panel)
	var row := UiKit.hbox(UiTokens.SP_3)
	card.body.add_child(row)
	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(200, 200)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring := TextureRect.new()
	ring.texture = ArtLib.ui("formation")
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.add_child(ring)
	var avatar := UiKit.icon("avatar_meditate", 120, UiTokens.GOLD_HOVER)
	avatar.set_anchors_preset(Control.PRESET_CENTER)
	avatar.offset_left = -60
	avatar.offset_right = 60
	avatar.offset_top = -60
	avatar.offset_bottom = 60
	portrait.add_child(avatar)
	row.add_child(portrait)
	var info := UiKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info)
	var realm := UiKit.label(str(_state.get("realmName", "—")), UiTokens.FS_HUGE - 8, UiTokens.TEXT)
	realm.add_theme_font_override("font", ArtLib.title_font())
	info.add_child(realm)
	var power_row := UiKit.hbox(UiTokens.SP_1)
	power_row.add_child(UiKit.icon("res_power", 52, UiTokens.GOLD))
	var power_label := UiKit.label("战力 %d" % int(_state.get("power", 0)), UiTokens.FS_H2, UiTokens.GOLD)
	power_row.add_child(power_label)
	info.add_child(power_row)
	info.add_child(UiKit.label("强化经验 %d" % model.enhance_exp, UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))


func _build_paper_doll(slots: Dictionary) -> void:
	var card := UiKit.card("装备栏")
	_root.add_child(card.panel)
	var doll := HBoxContainer.new()
	doll.add_theme_constant_override("separation", UiTokens.TAP_GAP)
	card.body.add_child(doll)
	var left := UiKit.vbox(UiTokens.TAP_GAP)
	var right := UiKit.vbox(UiTokens.TAP_GAP)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var center := PanelContainer.new()
	center.custom_minimum_size = Vector2(190, 0)
	center.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_theme_stylebox_override("panel", ArtLib.nine("panel_inset"))
	var figure := UiKit.vbox(UiTokens.SP_1)
	figure.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(figure)
	figure.add_child(UiKit.icon("avatar_meditate", 130, Color(UiTokens.GOLD, 0.85)))
	figure.add_child(UiKit.label("装备战力", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	figure.add_child(UiKit.label(str(EquipModel.gear_power(slots)), UiTokens.FS_BODY_L, UiTokens.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	doll.add_child(left)
	doll.add_child(center)
	doll.add_child(right)
	for slot in SlotConfig.core():
		var cell := _make_cell(slot, slots)
		(left if str(slot.get("side", "left")) == "left" else right).add_child(cell)
	var extra := UiKit.hbox(UiTokens.TAP_GAP)
	card.body.add_child(extra)
	for slot in SlotConfig.extra():
		extra.add_child(_make_cell(slot, slots))
	var worn := EquipModel.worn_count(slots)
	card.body.add_child(UiKit.wrap_label("已穿戴 %d / %d 件。法宝、灵宠在第三期开放。" % [worn, SlotConfig.core().size()], UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))


func _make_cell(slot: Dictionary, slots: Dictionary) -> EquipSlotCell:
	var cell := EquipSlotCell.new()
	var item: Dictionary = slots.get(str(slot.id), {})
	cell.setup(slot, item)
	cell.slot_pressed.connect(_on_slot)
	_cells[str(slot.id)] = cell
	return cell


func _build_attributes(slots: Dictionary) -> void:
	var card := UiKit.card("属性")
	_root.add_child(card.panel)
	var totals := EquipModel.stat_totals(slots)
	for key in BagModel.STAT_KEYS:
		var line := UiKit.hbox(UiTokens.SP_2)
		card.body.add_child(line)
		var name := UiKit.label(str(BagModel.STAT_NAMES[key]), UiTokens.FS_BODY, UiTokens.TEXT_MUTED)
		name.custom_minimum_size = Vector2(180, 0)
		line.add_child(name)
		var value := UiKit.label(str(BagModel.shown(float(_state.get(key, 0)))), UiTokens.FS_BODY_L, UiTokens.TEXT)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(value)
		line.add_child(UiKit.label("装备 +%d" % BagModel.shown(float(totals[key])), UiTokens.FS_CAPTION, UiTokens.JADE, HORIZONTAL_ALIGNMENT_RIGHT))


func _build_power() -> void:
	var breakdown := PowerBreakdown.compute(_state, _content)
	var card := UiKit.card("战力构成")
	_root.add_child(card.panel)
	var fills := {"output": "bar_fill_gold", "survival": "bar_fill_jade", "initiative": "bar_fill_blue"}
	for part in breakdown.parts:
		var line := UiKit.hbox(UiTokens.SP_2)
		card.body.add_child(line)
		var name := UiKit.label(str(part.name), UiTokens.FS_BODY, UiTokens.TEXT)
		name.custom_minimum_size = Vector2(120, 0)
		line.add_child(name)
		line.add_child(UiKit.ratio_bar(float(part.ratio), fills[part.id] as String, 44))
		var value := UiKit.label("%d · %d%%" % [int(part.value), int(round(float(part.ratio) * 100.0))], UiTokens.FS_CAPTION, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		value.custom_minimum_size = Vector2(240, 0)
		line.add_child(value)
		card.body.add_child(UiKit.label(str(part.hint), UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	var other := int(breakdown.other)
	var note := "合计 %d（服务器战力 %d）" % [int(breakdown.computed), int(breakdown.total)]
	if other != 0:
		note += "，其他加成 %+d（功法等）" % other
	card.body.add_child(UiKit.wrap_label(note, UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))


func _on_slot(slot_id: String) -> void:
	if popup == null:
		return
	var slot := SlotConfig.find(slot_id)
	var slots := EquipModel.slots_of(model)
	var item: Dictionary = slots.get(slot_id, {})
	if bool(slot.get("locked", false)) or not bool(slot.get("supported", false)):
		popup.clear_content()
		var reason := str(slot.get("note", "暂未开放"))
		popup.body.add_child(UiKit.wrap_label("「%s」%s。" % [str(slot.get("name", "")), reason], UiTokens.FS_BODY, UiTokens.TEXT))
		popup.set_actions([{"text": "知道了", "variation": MainTheme.VAR_PRIMARY}])
		popup.open_popup(str(slot.get("name", "")))
		return
	if item.is_empty():
		_show_picker(slot_id)
		return
	var handlers := {
		"unequip": func(id: String) -> void: action_requested.emit("unequip", [id]),
		"equip": func(_id: String) -> void: _show_picker(slot_id),
		"use": func(_id: String) -> void: pass,
		"enhance": func(id: String, to_max: bool) -> void: action_requested.emit("enhance_max" if to_max else "enhance", [id]),
		"breakthrough": func(id: String) -> void: action_requested.emit("breakthrough", [id]),
		"decompose": func(_id: String) -> void: pass,
	}
	ItemDetail.show_item(popup, item, {}, handlers, model.enhance_exp)
	# 已穿戴的详情里把"脱下"旁边加一个"换一件"。
	var grid := _find_grid(popup.body)
	if grid != null:
		var swap := UiKit.button("换一件", MainTheme.VAR_SECONDARY)
		swap.pressed.connect(func() -> void:
			popup.close_popup()
			_show_picker(slot_id))
		grid.add_child(swap)


## 强化后回到这件装备的详情（外壳调用）。
func show_detail(item_id: String) -> void:
	var item := model.find(item_id)
	if item.is_empty() or popup == null:
		return
	if bool(item.get("equipped", false)):
		_on_slot(str(item.get("equipped_slot_id", "")))
	else:
		ItemDetail.show_item(popup, item, EquipModel.worn_in(model, str(item.get("slot_id", ""))), {
			"equip": func(id: String) -> void: action_requested.emit("equip", [id]),
			"enhance": func(id: String, to_max: bool) -> void: action_requested.emit("enhance_max" if to_max else "enhance", [id]),
			"breakthrough": func(id: String) -> void: action_requested.emit("breakthrough", [id]),
			"decompose": func(_id: String) -> void: pass,
		}, model.enhance_exp)


func _find_grid(node: Node) -> GridContainer:
	for child in node.get_children():
		if child is GridContainer:
			return child as GridContainer
	return null


## 空部位或"换一件"：列出行囊里这个部位的装备，显示相对当前的战力变化。
func _show_picker(slot_id: String) -> void:
	var slot := SlotConfig.find(slot_id)
	var current := EquipModel.worn_in(model, slot_id)
	var candidates := EquipModel.candidates_for(model, slot_id)
	popup.clear_content()
	if candidates.is_empty():
		popup.body.add_child(UiKit.wrap_label("行囊里没有可穿戴的「%s」。去历练打首领可以掉落。" % str(slot.get("name", "")), UiTokens.FS_BODY, UiTokens.TEXT))
		popup.set_actions([{"text": "知道了", "variation": MainTheme.VAR_PRIMARY}])
		popup.open_popup("选择%s" % str(slot.get("name", "")))
		return
	if not current.is_empty():
		popup.body.add_child(UiKit.label("当前：%s  战力 %d" % [str(current.name), int(current.power)], UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
	for item in candidates:
		var delta := int(item.power) - int(current.get("power", 0))
		var row := Button.new()
		row.custom_minimum_size = Vector2(0, UiTokens.H_TOUCH + 16)
		row.theme_type_variation = MainTheme.VAR_CHOICE
		row.text = "%s · %s    战力 %d  %s" % [str(item.name), str(item.rarity_name), int(item.power), ("▲ +%d" % delta) if delta > 0 else ("▼ %d" % delta if delta < 0 else "－")]
		row.add_theme_color_override("font_color", UiTokens.rarity_color(int(item.rarity)))
		row.add_theme_font_size_override("font_size", UiTokens.FS_CAPTION)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var id := str(item.id)
		row.pressed.connect(func() -> void:
			popup.close_popup()
			action_requested.emit("equip", [id]))
		popup.body.add_child(row)
	popup.open_popup("选择%s" % str(slot.get("name", "")))
