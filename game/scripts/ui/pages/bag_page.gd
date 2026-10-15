class_name BagPage
extends VBoxContainer
## 背包页（装备栏已并入，设计稿 05）：标题、分类页签（全部/装备/丹药/材料）、装备栏（6 个部位 + 2 个锁定预留位）、
## 背包容量 + 一键穿戴 / 整理 / 批量、自动分解开关行、5 列 × 4 行格子（初始容量 20）。
## 点格子或装备栏部位弹出物品详情（强化 / 穿戴 / 脱下 / 分解；已穿戴的分解按钮灰掉并写「已穿戴，无法分解」）。
## 数据通过 bind(state, content, flags) 传入；操作通过 action_requested 发出，由外壳调接口，不直接访问网络。

## kind: equip / unequip / use / enhance / enhance_max / breakthrough / decompose / auto_decompose / equip_many；
## ids: 物品 id 数组（auto_decompose 时是 [bool]）。
signal action_requested(kind: String, ids: Array)

const COLUMNS := 5
const ROWS := 4
const TABS: Array[Dictionary] = [
	{"id": "all", "name": "全部"},
	{"id": "equip", "name": "装备"},
	{"id": "pill", "name": "丹药"},
	{"id": "material", "name": "材料"},
]

var popup: GamePopup
var model: BagModel = BagModel.new()
var flags: ItemFlags
var category := "all"
var sort_index := 0
var auto_decompose := false

var _state: Dictionary = {}
var _content: Dictionary = {}
var _tabs: SegTabs
var _doll_row: HBoxContainer
var _doll_note: Label
var _cells: Dictionary = {}
var _capacity_label: Label
var _wear_button: Button
var _sort_button: Button
var _batch_button: Button
var _auto_label: Label
var _auto_switch: Button
var _auto_icon: TextureRect
var _auto_text: Label
var _grid: ItemGrid
var _batch_bar: HBoxContainer
var _selected_label: Label
var _decompose_button: Button
var _hint: Label
var _empty: Label


func _init() -> void:
	add_theme_constant_override("separation", UiTokens.SP_1)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()


func _build() -> void:
	add_child(UiKit.page_title("背包"))
	_tabs = SegTabs.new()
	_tabs.tab_changed.connect(_on_tab)
	add_child(_tabs)
	add_child(_build_doll())
	add_child(_build_capacity_row())
	add_child(_build_auto_row())
	_grid = ItemGrid.new()
	_grid.set_columns(COLUMNS)
	_grid.selectable = BagModel.selectable_for_batch
	_grid.slot_pressed.connect(_on_slot)
	_grid.selection_changed.connect(_on_selection)
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", ArtLib.nine("panel_inset"))
	frame.add_child(_grid)
	add_child(frame)
	_empty = UiKit.wrap_label("这个分类里还没有东西。去历练打首领，会掉落装备和材料。", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED)
	_empty.visible = false
	add_child(_empty)
	_hint = UiKit.wrap_label("", UiTokens.FS_CAPTION, UiTokens.JADE)
	_hint.visible = false
	add_child(_hint)
	_batch_bar = UiKit.hbox(UiTokens.TAP_GAP)
	_batch_bar.visible = false
	add_child(_batch_bar)
	_selected_label = UiKit.label("已选 0 件", UiTokens.FS_CAPTION, UiTokens.TEXT)
	_selected_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_batch_bar.add_child(_selected_label)
	var all_button := UiKit.button("全选", MainTheme.VAR_SECONDARY)
	all_button.custom_minimum_size = Vector2(160, UiTokens.H_TOUCH)
	all_button.pressed.connect(func() -> void: _grid.select_all())
	_batch_bar.add_child(all_button)
	_decompose_button = UiKit.button("分解所选", MainTheme.VAR_DANGER)
	_decompose_button.custom_minimum_size = Vector2(280, UiTokens.H_TOUCH)
	_decompose_button.disabled = true
	_decompose_button.pressed.connect(_confirm_batch)
	_batch_bar.add_child(_decompose_button)


func _build_doll() -> Control:
	var card := PanelContainer.new()
	card.name = "EquipBar"
	card.add_theme_stylebox_override("panel", ArtLib.nine("panel_card"))
	var column := UiKit.vbox(UiTokens.SP_1)
	card.add_child(column)
	var head := UiKit.hbox(UiTokens.SP_1)
	column.add_child(head)
	head.add_child(UiKit.label("装备栏", UiTokens.FS_CAPTION, UiTokens.GOLD))
	_doll_note = UiKit.label("", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_doll_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_doll_note)
	_doll_row = UiKit.hbox(6)
	column.add_child(_doll_row)
	return card


func _build_capacity_row() -> Control:
	var row := UiKit.hbox(UiTokens.SP_1)
	_capacity_label = UiKit.label("背包容量 0 / 20", UiTokens.FS_CAPTION, UiTokens.TEXT)
	_capacity_label.name = "CapacityLabel"
	_capacity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_capacity_label)
	_wear_button = UiKit.button("一键穿戴", MainTheme.VAR_SECONDARY, 80)
	_wear_button.name = "WearAllButton"
	_wear_button.custom_minimum_size = Vector2(210, 80)
	_wear_button.pressed.connect(_on_wear_all)
	row.add_child(_wear_button)
	_sort_button = UiKit.button("整理", MainTheme.VAR_SECONDARY, 80)
	_sort_button.name = "SortButton"
	_sort_button.custom_minimum_size = Vector2(150, 80)
	_sort_button.pressed.connect(_tidy)
	row.add_child(_sort_button)
	_batch_button = UiKit.button("批量", MainTheme.VAR_SECONDARY, 80)
	_batch_button.name = "BatchButton"
	_batch_button.custom_minimum_size = Vector2(150, 80)
	_batch_button.pressed.connect(_toggle_batch)
	row.add_child(_batch_button)
	return row


## 自动分解开关行：整行可点。文字固定为「自动分解（仅未强化的白、绿装备）」。
func _build_auto_row() -> Control:
	_auto_switch = Button.new()
	_auto_switch.name = "AutoDecomposeRow"
	_auto_switch.custom_minimum_size = Vector2(0, 88)
	_auto_switch.focus_mode = Control.FOCUS_NONE
	var frame := ArtLib.nine("chip")
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		_auto_switch.add_theme_stylebox_override(state, frame if state != "focus" else StyleBoxEmpty.new())
	_auto_switch.pressed.connect(func() -> void: action_requested.emit("auto_decompose", [not auto_decompose]))
	var row := UiKit.hbox(UiTokens.SP_1)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 20
	row.offset_right = -20
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_auto_switch.add_child(row)
	_auto_label = UiKit.label("自动分解（仅未强化的白、绿装备）", UiTokens.FS_CAPTION, UiTokens.TEXT)
	_auto_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auto_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_auto_label.clip_text = true
	row.add_child(_auto_label)
	_auto_text = UiKit.label("关", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED)
	_auto_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_auto_text)
	_auto_icon = UiKit.icon_from(ArtLib.switch_tex(false), 80, Color.WHITE)
	_auto_icon.custom_minimum_size = Vector2(120, 60)
	_auto_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_auto_icon)
	return _auto_switch


func bind(state: Dictionary, content: Dictionary, item_flags: ItemFlags) -> void:
	_state = state
	_content = content
	flags = item_flags
	auto_decompose = bool(state.get("autoDecompose", false))
	refresh()


func refresh() -> void:
	var seen: Dictionary = flags.seen if flags != null else {}
	model = BagModel.from_state(_state, _content, seen)
	var used := model.used_slots()
	_capacity_label.text = "背包容量 %d / %d" % [used, model.capacity]
	_capacity_label.add_theme_color_override("font_color", UiTokens.WARNING if model.is_full() else UiTokens.TEXT)
	var tabs: Array = []
	for entry in TABS:
		tabs.append({"id": entry.id, "name": entry.name})
	_tabs.set_tabs(tabs, category)
	_auto_text.text = "开" if auto_decompose else "关"
	_auto_text.add_theme_color_override("font_color", UiTokens.GOLD_HOVER if auto_decompose else UiTokens.TEXT_MUTED)
	_auto_icon.texture = ArtLib.switch_tex(auto_decompose)
	_render_doll()
	_wear_button.disabled = EquipModel.best_upgrades(model).is_empty()
	_render_grid()


func _render_doll() -> void:
	UiKit.clear(_doll_row)
	_cells.clear()
	var slots := EquipModel.slots_of(model)
	for slot in SlotConfig.all():
		var cell := EquipSlotCell.new()
		cell.make_compact(108.0, 150.0)
		cell.setup(slot, slots.get(str(slot.id), {}))
		cell.slot_pressed.connect(_on_equip_slot)
		_doll_row.add_child(cell)
		_cells[str(slot.id)] = cell
	_doll_note.text = "%d 个部位 · 法宝、灵宠第三期开放" % SlotConfig.core().size()


func equip_cell(slot_id: String) -> EquipSlotCell:
	return _cells.get(slot_id, null) as EquipSlotCell


func auto_switch() -> Button:
	return _auto_switch


func show_hint(text: String) -> void:
	_hint.text = text
	_hint.visible = not text.is_empty()


func _render_grid() -> void:
	var list := model.visible_items(category, str(BagModel.SORTS[sort_index].id))
	_grid.set_items(list, ROWS, model.capacity)
	_empty.visible = list.is_empty()


## 打开背包页后，当前看到的物品都算"已看过"，下次进来就不再显示"新"。
func mark_visible_seen() -> void:
	if flags == null:
		return
	var ids: Array = []
	for item in model.visible_items("all"):
		ids.append(item.id)
	flags.mark_seen(ids)


func _on_tab(tab_id: String) -> void:
	category = tab_id
	if _grid.multi_select:
		_grid.set_multi_select(false)
		_leave_batch()
	_render_grid()


## 整理：按品质（再按战力）从高到低排。
func _tidy() -> void:
	sort_index = 1
	_render_grid()
	show_hint("已按品质整理")


func _on_wear_all() -> void:
	var ids := EquipModel.best_upgrades(model)
	if ids.is_empty():
		return
	action_requested.emit("equip_many", ids)


func _toggle_batch() -> void:
	var on := not _grid.multi_select
	if on and category != "equip" and category != "all":
		_tabs.select("equip", true)
		category = "equip"
		_render_grid()
	_grid.set_multi_select(on)
	_batch_bar.visible = on
	_batch_button.text = "完成" if on else "批量"
	_batch_button.theme_type_variation = MainTheme.VAR_PRIMARY if on else MainTheme.VAR_SECONDARY
	_on_selection([])


func _leave_batch() -> void:
	_batch_bar.visible = false
	_batch_button.text = "批量"
	_batch_button.theme_type_variation = MainTheme.VAR_SECONDARY


func _on_selection(ids: Array) -> void:
	var valid := model.batch_ids(ids)
	var gain := 0
	for id in valid:
		gain += int(model.find(id).get("decompose_exp", 0))
	_selected_label.text = "已选 %d 件" % valid.size() if valid.is_empty() else "已选 %d 件 · +%d 强化经验" % [valid.size(), gain]
	_decompose_button.disabled = valid.is_empty()


func _on_slot(item: Dictionary) -> void:
	if popup == null:
		return
	if _grid.multi_select:
		show_hint("「%s」不能批量分解：%s" % [str(item.get("name", "")), _why_not(item)])
		return
	var worn := {}
	if str(item.get("category", "")) == "equip":
		worn = EquipModel.worn_in(model, str(item.get("slot_id", "")))
	ItemDetail.show_item(popup, item, worn, _handlers(), model.enhance_exp)


## 强化后回到这件物品的详情（外壳调用）。
func show_detail(item_id: String) -> void:
	var item := model.find(item_id)
	if item.is_empty() or popup == null:
		return
	if bool(item.get("equipped", false)):
		_on_equip_slot(str(item.get("equipped_slot_id", "")))
	else:
		_on_slot(item)


func _why_not(item: Dictionary) -> String:
	if str(item.get("category", "")) != "equip":
		return "只有装备可以分解"
	return "已穿戴"


func _handlers() -> Dictionary:
	return {
		"equip": func(id: String) -> void: action_requested.emit("equip", [id]),
		"unequip": func(id: String) -> void: action_requested.emit("unequip", [id]),
		"use": func(id: String) -> void: action_requested.emit("use", [id]),
		"enhance": func(id: String, to_max: bool) -> void: action_requested.emit("enhance_max" if to_max else "enhance", [id]),
		"breakthrough": func(id: String) -> void: action_requested.emit("breakthrough", [id]),
		"decompose": func(id: String) -> void: _confirm_single(id),
	}


## 装备栏部位：有装备→详情（可脱下 / 强化 / 换一件；分解灰掉）；空→挑一件；锁定位→说明。
func _on_equip_slot(slot_id: String) -> void:
	if popup == null:
		return
	var slot := SlotConfig.find(slot_id)
	var slots := EquipModel.slots_of(model)
	var item: Dictionary = slots.get(slot_id, {})
	if bool(slot.get("locked", false)) or not bool(slot.get("supported", false)):
		popup.clear_content()
		popup.body.add_child(UiKit.wrap_label("「%s」%s。" % [str(slot.get("name", "")), str(slot.get("note", "暂未开放"))], UiTokens.FS_BODY, UiTokens.TEXT))
		popup.set_actions([{"text": "知道了", "variation": MainTheme.VAR_PRIMARY}])
		popup.open_popup(str(slot.get("name", "")))
		return
	if item.is_empty():
		_show_picker(slot_id)
		return
	var handlers := _handlers()
	handlers["equip"] = func(_id: String) -> void: _show_picker(slot_id)
	ItemDetail.show_item(popup, item, {}, handlers, model.enhance_exp)
	var grid := _find_grid(popup.body)
	if grid != null:
		var swap := UiKit.button("换一件", MainTheme.VAR_SECONDARY)
		swap.pressed.connect(func() -> void:
			popup.close_popup()
			_show_picker(slot_id))
		grid.add_child(swap)


func _find_grid(node: Node) -> GridContainer:
	for child in node.get_children():
		if child is GridContainer:
			return child as GridContainer
	return null


## 空部位或「换一件」：列出背包里这个部位的装备，显示相对当前的战力变化。
func _show_picker(slot_id: String) -> void:
	var slot := SlotConfig.find(slot_id)
	var current := EquipModel.worn_in(model, slot_id)
	var candidates := EquipModel.candidates_for(model, slot_id)
	popup.clear_content()
	if candidates.is_empty():
		popup.body.add_child(UiKit.wrap_label("背包里没有可穿戴的「%s」。去历练打首领可以掉落。" % str(slot.get("name", "")), UiTokens.FS_BODY, UiTokens.TEXT))
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


func _confirm_single(id: String) -> void:
	var item := model.find(id)
	if item.is_empty():
		return
	var message := "分解「%s」会得到 %d 强化经验，物品将消失。此操作不能撤销。" % [str(item.name), int(item.get("decompose_exp", 0))]
	if int(item.get("enhance", 0)) > 0:
		message += "\n已投入的强化经验会按比例返还。"
	ItemDetail.show_confirm(popup, "确认分解", message, "确认分解", func() -> void: action_requested.emit("decompose", [id]))


func _confirm_batch() -> void:
	var ids := model.batch_ids(_grid.selected_ids())
	if ids.is_empty():
		return
	var rare := 0
	var gain := 0
	for id in ids:
		if int(model.find(id).get("rarity", 0)) >= 3:
			rare += 1
		gain += int(model.find(id).get("decompose_exp", 0))
	var message := "将分解 %d 件装备，共得到 %d 强化经验，物品将消失，不能撤销。" % [ids.size(), gain]
	if rare > 0:
		message += "\n其中有 %d 件珍品及以上，请再确认。" % rare
	ItemDetail.show_confirm(popup, "批量分解", message, "分解 %d 件" % ids.size(), func() -> void:
		_grid.set_multi_select(false)
		_leave_batch()
		action_requested.emit("decompose", ids))
