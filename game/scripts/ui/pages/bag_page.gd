class_name BagPage
extends VBoxContainer
## 行囊页：容量（初始 20 格）、强化经验、分类页签（装备/材料/丹药/其他）、排序、物品格子网格、点格子看详情、批量分解。
## 数据通过 bind(state, content, flags) 传入；操作通过 action_requested 发出去，由外壳去调接口。
## 不直接访问网络，所以既能接真实数据，也能接 UiMock。

## kind: equip / unequip / use / enhance / enhance_max / breakthrough / decompose / auto_decompose；
## ids: 物品 id 数组（auto_decompose 时是 [bool]）。
signal action_requested(kind: String, ids: Array)

const COLUMNS := 5

var popup: GamePopup
var model: BagModel = BagModel.new()
var flags: ItemFlags
var category := "equip"
var sort_index := 0
var auto_decompose := false

var _state: Dictionary = {}
var _content: Dictionary = {}
var _title: Label
var _capacity_bar: Control
var _capacity_box: VBoxContainer
var _capacity_label: Label
var _exp_chip: PanelContainer
var _tabs: SegTabs
var _grid: ItemGrid
var _sort_button: Button
var _batch_button: Button
var _batch_bar: HBoxContainer
var _selected_label: Label
var _decompose_button: Button
var _hint: Label
var _auto_button: Button
var _empty: Label


func _init() -> void:
	add_theme_constant_override("separation", UiTokens.SP_2)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()


func _build() -> void:
	var head := UiKit.hbox(UiTokens.SP_2)
	add_child(head)
	_title = UiKit.label("行囊", UiTokens.FS_H1, UiTokens.GOLD)
	_title.add_theme_font_override("font", ArtLib.title_font())
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_exp_chip = UiKit.chip("res_enhance", "强化经验 0", UiTokens.GOLD)
	head.add_child(_exp_chip)
	var capacity_row := UiKit.hbox(UiTokens.SP_2)
	add_child(capacity_row)
	_capacity_box = UiKit.vbox(0)
	_capacity_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_capacity_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	capacity_row.add_child(_capacity_box)
	_capacity_label = UiKit.label("容量 0 / 20", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED)
	capacity_row.add_child(_capacity_label)
	_sort_button = UiKit.button("排序：默认", MainTheme.VAR_SECONDARY)
	_sort_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_sort_button.custom_minimum_size = Vector2(0, UiTokens.H_TOUCH)
	_sort_button.pressed.connect(_cycle_sort)
	_batch_button = UiKit.button("批量", MainTheme.VAR_SECONDARY)
	_batch_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_batch_button.custom_minimum_size = Vector2(0, UiTokens.H_TOUCH)
	_batch_button.pressed.connect(_toggle_batch)

	_tabs = SegTabs.new()
	_tabs.tab_changed.connect(_on_tab)
	add_child(_tabs)
	var tools := UiKit.hbox(UiTokens.TAP_GAP)
	add_child(tools)
	_sort_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_batch_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(_sort_button)
	tools.add_child(_batch_button)

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
	_selected_label = UiKit.label("已选 0 件", UiTokens.FS_BODY, UiTokens.TEXT)
	_selected_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_batch_bar.add_child(_selected_label)
	var all_button := UiKit.button("全选", MainTheme.VAR_SECONDARY)
	all_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	all_button.custom_minimum_size = Vector2(180, UiTokens.H_TOUCH)
	all_button.pressed.connect(func() -> void: _grid.select_all())
	_batch_bar.add_child(all_button)
	_decompose_button = UiKit.button("分解所选", MainTheme.VAR_DANGER)
	_decompose_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_decompose_button.custom_minimum_size = Vector2(300, UiTokens.H_TOUCH)
	_decompose_button.disabled = true
	_decompose_button.pressed.connect(_confirm_batch)
	_batch_bar.add_child(_decompose_button)

	_auto_button = UiKit.button("", MainTheme.VAR_GHOST)
	_auto_button.add_theme_font_size_override("font_size", UiTokens.FS_CAPTION)
	_auto_button.pressed.connect(func() -> void: action_requested.emit("auto_decompose", [not auto_decompose]))
	add_child(_auto_button)


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
	_capacity_label.text = "容量 %d / %d" % [used, model.capacity]
	(_exp_chip.find_child("Text", true, false) as Label).text = "强化经验 %d" % model.enhance_exp
	if _capacity_bar != null:
		_capacity_box.remove_child(_capacity_bar)
		_capacity_bar.queue_free()
	var near_full := float(used) >= float(model.capacity) * 0.9
	_capacity_bar = UiKit.ratio_bar(float(used) / float(maxi(model.capacity, 1)), "bar_fill_gold" if near_full else "bar_fill_jade", 44)
	_capacity_box.add_child(_capacity_bar)
	_capacity_label.add_theme_color_override("font_color", UiTokens.WARNING if model.is_full() else UiTokens.TEXT_MUTED)
	var tabs: Array = []
	for entry in BagModel.CATEGORIES:
		tabs.append({"id": entry.id, "name": entry.name, "badge": str(model.category_count(str(entry.id)))})
	_tabs.set_tabs(tabs, category)
	_auto_button.text = "自动分解不如身上的装备：%s（点击切换）" % ("开" if auto_decompose else "关")
	_sort_button.text = "排序：%s" % str(BagModel.SORTS[sort_index].name)
	_render_grid()


func show_hint(text: String) -> void:
	_hint.text = text
	_hint.visible = not text.is_empty()


func _render_grid() -> void:
	var list := model.visible_items(category, str(BagModel.SORTS[sort_index].id))
	_grid.set_items(list, 5, model.capacity)
	_empty.visible = list.is_empty()


## 打开行囊页后，当前看到的物品都算"已看过"，下次进来就不再显示"新"。
func mark_visible_seen() -> void:
	if flags == null:
		return
	var ids: Array = []
	for item in model.visible_items(category):
		ids.append(item.id)
	flags.mark_seen(ids)


func _on_tab(tab_id: String) -> void:
	category = tab_id
	if _grid.multi_select:
		_grid.set_multi_select(false)
		_leave_batch()
	_render_grid()


func _cycle_sort() -> void:
	sort_index = (sort_index + 1) % BagModel.SORTS.size()
	_sort_button.text = "排序：%s" % str(BagModel.SORTS[sort_index].name)
	_render_grid()


func _toggle_batch() -> void:
	var on := not _grid.multi_select
	if on and category != "equip":
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
	if not item.is_empty() and popup != null:
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
	for id in ids:
		if int(model.find(id).get("rarity", 0)) >= 3:
			rare += 1
	var gain := 0
	for id in ids:
		gain += int(model.find(id).get("decompose_exp", 0))
	var message := "将分解 %d 件装备，共得到 %d 强化经验，物品将消失，不能撤销。" % [ids.size(), gain]
	if rare > 0:
		message += "\n其中有 %d 件珍品及以上，请再确认。" % rare
	ItemDetail.show_confirm(popup, "批量分解", message, "分解 %d 件" % ids.size(), func() -> void:
		_grid.set_multi_select(false)
		_leave_batch()
		action_requested.emit("decompose", ids))
