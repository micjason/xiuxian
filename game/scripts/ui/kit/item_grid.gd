class_name ItemGrid
extends ScrollContainer
## 可滚动的物品格子网格。负责：按列数排布、空格补位（显示容量）、单选点击、多选勾选。
## 不关心数据从哪来：调用 set_items(展示字典数组)。点击发 slot_pressed，多选变化发 selection_changed。

signal slot_pressed(item: Dictionary)
signal selection_changed(ids: Array)

var columns := 5
var multi_select := false
## 多选时哪些物品允许被勾选；返回 false 的格子会变暗且点不了。
var selectable: Callable = func(_item: Dictionary) -> bool: return true

var _grid: GridContainer
var _selected: Dictionary = {}
var _slots: Array[ItemSlot] = []
var _sig := 0
## set_items 真正改动格子的次数（测试 / 测量用）。
var rebuilds := 0


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid = GridContainer.new()
	_grid.columns = columns
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", UiTokens.TAP_GAP)
	_grid.add_theme_constant_override("v_separation", UiTokens.TAP_GAP)
	add_child(_grid)


func set_columns(value: int) -> void:
	columns = maxi(1, value)
	_grid.columns = columns


## min_rows：至少显示几行（空格补位）；max_cells：补位的格数上限（一般是容量）。
## v14：格子复用，不再每次全删全建（原来每次心跳刷新都重建 20+ 个按钮：滚动中被打断、按住的格子消失、卡一下）；
## 列表和上次完全一样时直接跳过。
func set_items(items: Array[Dictionary], min_rows: int = 5, max_cells: int = 0) -> void:
	var keep := {}
	for item in items:
		keep[str(item.get("id", ""))] = true
	for id in _selected.keys():
		if not keep.has(id):
			_selected.erase(id)
	var rows := maxi(min_rows, int(ceil(float(items.size()) / float(columns))))
	var cells := rows * columns
	if max_cells > 0:
		cells = mini(cells, max_cells)
	cells = maxi(cells, items.size())
	var sig := hash([items, cells, multi_select, _selected.keys()])
	if sig == _sig and _slots.size() == cells:
		return
	_sig = sig
	while _slots.size() > cells:
		var extra: ItemSlot = _slots.pop_back()
		_grid.remove_child(extra)
		extra.queue_free()
	while _slots.size() < cells:
		var slot := ItemSlot.new()
		slot.item_pressed.connect(_on_slot)
		_grid.add_child(slot)
		_slots.append(slot)
	rebuilds += 1
	for index in cells:
		var slot := _slots[index]
		if index < items.size():
			var item := items[index]
			slot.set_item(item)
			slot.set_selected(_selected.has(str(item.get("id", ""))))
			slot.set_dimmed(multi_select and not bool(selectable.call(item)))
		else:
			slot.set_empty()
			slot.set_dimmed(false)


func slot_count() -> int:
	return _slots.size()


func filled_count() -> int:
	var count := 0
	for slot in _slots:
		if not slot.is_empty_slot():
			count += 1
	return count


func set_multi_select(on: bool) -> void:
	multi_select = on
	if not on:
		clear_selection()
	for slot in _slots:
		if slot.is_empty_slot():
			continue
		slot.set_dimmed(on and not bool(selectable.call(slot.item)))


func selected_ids() -> Array:
	return _selected.keys()


func clear_selection() -> void:
	_selected.clear()
	for slot in _slots:
		slot.set_selected(false)
	selection_changed.emit([])


func select_all() -> void:
	for slot in _slots:
		if not slot.is_empty_slot() and bool(selectable.call(slot.item)):
			_selected[str(slot.item.get("id", ""))] = true
			slot.set_selected(true)
	selection_changed.emit(_selected.keys())


func _on_slot(item: Dictionary) -> void:
	if item.is_empty() or ScrollKit.tap_blocked():
		return
	if not multi_select:
		slot_pressed.emit(item)
		return
	if not bool(selectable.call(item)):
		slot_pressed.emit(item)
		return
	var id := str(item.get("id", ""))
	if _selected.has(id):
		_selected.erase(id)
	else:
		_selected[id] = true
	for slot in _slots:
		if str(slot.item.get("id", "")) == id:
			slot.set_selected(_selected.has(id))
	selection_changed.emit(_selected.keys())
