class_name BagPage
extends VBoxContainer
## 背包页（Q 版设计稿 q_bag）：纸娃娃（境界绶带 + 6 个部位 + 法宝/灵宠锁定位）、战力与四项属性、
## 筛选页签（全部/装备/丹药/材料）+ 容量、6 列格子（初始容量 20），底部 一键出售（未开放）/一键穿戴/分解/整理。
## 第五批（SPEC_Q §17.2）：去掉「自动分解」开关和背包内批量多选；「分解」打开居中的分解弹窗（kit/salvage_dialog.gd，外壳管）。
## 点格子或装备栏部位弹出物品详情（强化 / 穿戴 / 脱下 / 分解；已穿戴的分解按钮灰掉并写「已穿戴，无法分解」）。
## 数据通过 bind(state, content, flags) 传入；操作通过 action_requested 发出，由外壳调接口，不直接访问网络。

## kind: equip / unequip / use / enhance / enhance_max / breakthrough / decompose / open_salvage / equip_many / toast；
## ids: 物品 id 数组（open_salvage 时为空；toast 时是 [文字]）。
signal action_requested(kind: String, ids: Array)

const COLUMNS := 6
const ROWS := 4
## 纸娃娃格位置（卡内坐标，设计稿换算）：左列 武器/头冠/衣服，右列 护腕/靴子/饰品，下面 法宝/灵宠。
const DOLL_POS := {
	"weapon": Vector2(48, 86), "helmet": Vector2(48, 280), "clothes": Vector2(48, 474),
	"gloves": Vector2(834, 86), "shoes": Vector2(834, 280), "accessory": Vector2(834, 474),
	"artifact": Vector2(332, 600), "pet": Vector2(600, 600),
}
const STAT_CELLS := [
	{"key": "hp", "name": "生命", "cut": "icon_heart", "icon": "", "color": Color("e5484d")},
	{"key": "attack", "name": "攻击", "cut": "", "icon": "gear_weapon", "color": Color("ea7a1e")},
	{"key": "defense", "name": "防御", "cut": "icon_shield", "icon": "", "color": Color("2e7fd0")},
	{"key": "speed", "name": "速度", "cut": "", "icon": "gear_shoes", "color": Color("2f9e5b")},
]
const TABS: Array[Dictionary] = [
	{"id": "all", "name": "全部"},
	{"id": "equip", "name": "装备"},
	{"id": "pill", "name": "丹药"},
	{"id": "material", "name": "材料"},
]

var popup: GamePopup
## 物品详情弹窗（Q 版，scenes/ui/item_detail_popup.tscn）；没有时退回旧的 GamePopup 版（单独测试页面时）。
var detail_popup: ItemDetailPopup
var model: BagModel = BagModel.new()
var flags: ItemFlags
var category := "all"
var sort_index := 0

var _state: Dictionary = {}
var _content: Dictionary = {}
var _tabs: SegTabs
var _doll_row: Control
var _doll_note: Label
var _cells: Dictionary = {}
var _capacity_label: Label
var _wear_button: Button
var _sort_button: Button
var _salvage_button: Button
var _grid: ItemGrid
var _hint: Label
var _empty: Label
var _sell_button: Button
var _power_value: Label
var _stat_labels: Dictionary = {}
var _bind_sig := 0
var _bound_content: Dictionary = {}
## refresh 次数（测试 / 测量用）。
var refresh_count := 0


func _init() -> void:
	add_theme_constant_override("separation", 20)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()


func _build() -> void:
	add_child(_build_doll())
	add_child(_build_stats())
	var filter_row := UiKit.hbox(14)
	filter_row.name = "FilterRow"
	add_child(filter_row)
	_tabs = SegTabs.new()
	_tabs.q_style = true
	_tabs.add_theme_constant_override("separation", 14)
	_tabs.tab_changed.connect(_on_tab)
	filter_row.add_child(_tabs)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_row.add_child(spacer)
	filter_row.add_child(_build_capacity_pill())
	var frame := PanelContainer.new()
	frame.name = "GridCard"
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", QKit.cut_box("panel_cream", 22, 18))
	var column := UiKit.vbox(10)
	frame.add_child(column)
	_grid = ItemGrid.new()
	_grid.name = "BagGrid"
	_grid.set_columns(COLUMNS)
	_grid.slot_pressed.connect(_on_slot)
	var well := PanelContainer.new()
	well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	well.add_theme_stylebox_override("panel", QKit.cut_box("well_bag_grid", 16, 16) if ArtLib.qui("well_bag_grid") != null else ArtLib.nine("panel_inset"))
	well.add_child(_grid)
	column.add_child(well)
	_empty = UiKit.wrap_label("这个分类里还没有东西。去历练打首领，会掉落装备和材料。", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED)
	_empty.visible = false
	column.add_child(_empty)
	add_child(frame)
	_hint = UiKit.wrap_label("", UiTokens.FS_MICRO, UiTokens.Q_TEAL_DARK)
	_hint.visible = false
	add_child(_hint)
	add_child(_build_capacity_row())
	var orb_room := Control.new()
	orb_room.name = "OrbRoom"
	orb_room.custom_minimum_size = Vector2(0, 110)
	orb_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(orb_room)


## 纸娃娃（设计稿 36,252,1008,700）：浅青底、境界绶带、打坐小人 + 莲台，左 武器/头冠/衣服、右 护腕/靴子/饰品，下面两个锁定位 法宝/灵宠。
func _build_doll() -> Control:
	var card := Control.new()
	card.name = "EquipBar"
	card.custom_minimum_size = Vector2(0, 700)
	var back := Panel.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_theme_stylebox_override("panel", QKit.cut_box("panel_cream", 0, 0))
	card.add_child(back)
	var well := Panel.new()
	well.set_anchors_preset(Control.PRESET_FULL_RECT)
	well.offset_left = 22
	well.offset_top = 20
	well.offset_right = -22
	well.offset_bottom = -26
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_theme_stylebox_override("panel", QKit.cut_box("well_teal", 0, 0) if ArtLib.qui("well_teal") != null else QSkin.custom(Color("d9f3ee"), Color(0, 0, 0, 0), 0, 28, 0, 0, 0))
	card.add_child(well)
	## 设计稿的圆台：奶油色椭圆 + 杏色描边（美术没出这张，代码画）。
	var stage := Panel.new()
	stage.name = "DollStage"
	stage.position = Vector2(286, 480)
	stage.size = Vector2(460, 110)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_theme_stylebox_override("panel", QSkin.custom(Color("fbe7c6"), Color("e9c99a"), 6, 230, 0, 0, 0))
	card.add_child(stage)
	var hero := QHero.new(false, false)  # 动画主角（拆层拼合），只要人物；下面是代码画的圆台
	hero.name = "DollHero"
	hero.position = Vector2(296, 96)
	hero.size = Vector2(440, 440)
	card.add_child(hero)
	var ribbon := QKit.ribbon("", 40, 300, false)
	ribbon.name = "DollRibbon"
	ribbon.position = Vector2(366, 10)
	card.add_child(ribbon)
	_doll_note = ribbon.find_child("RibbonText", true, false) as Label
	_doll_row = Control.new()
	_doll_row.name = "DollSlots"
	_doll_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_doll_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_doll_row)
	return card


func _sprite(slug: String, rect: Rect2) -> TextureRect:
	var node := TextureRect.new()
	node.texture = ArtLib.q("sprites/" + slug) if ArtLib.has_q("sprites/%s.png" % slug) else null
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## 战力 + 四项属性（设计稿 36,974,1008,166）。全部取自玩家状态（power / hp / attack / defense / speed）。
func _build_stats() -> Control:
	var card := PanelContainer.new()
	card.name = "StatsCard"
	card.custom_minimum_size = Vector2(0, 166)
	card.add_theme_stylebox_override("panel", QKit.cut_box("panel_cream", 26, 14))
	var row := UiKit.hbox(14)
	card.add_child(row)
	var power := UiKit.vbox(0)
	power.custom_minimum_size = Vector2(170, 0)
	power.alignment = BoxContainer.ALIGNMENT_CENTER
	power.add_child(QKit.title("战力", 30, UiTokens.TEXT_MUTED))
	_power_value = QKit.outlined("0", 60, UiTokens.Q_GOLD, UiTokens.Q_COCOA, 10)
	_power_value.name = "PowerValue"
	power.add_child(_power_value)
	row.add_child(power)
	for spec in STAT_CELLS:
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_stylebox_override("panel", QKit.cut_box("well_apricot", 12, 8))
		var inner := UiKit.hbox(6)
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_child(inner)
		var icon: Control
		if not str(spec.cut).is_empty():
			icon = QKit.cut_rect(str(spec.cut), Vector2(52, 52))
		else:
			var rect := TextureRect.new()
			rect.texture = ArtLib.q("items/" + str(spec.icon)) if ArtLib.has_q("items/%s.png" % spec.icon) else ArtLib.icon(str(spec.icon))
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon = rect
		icon.custom_minimum_size = Vector2(52, 52)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inner.add_child(icon)
		var texts := UiKit.vbox(0)
		texts.add_child(QKit.title(str(spec.name), 30, UiTokens.TEXT_MUTED))
		var value := QKit.title("0", 40, spec.color as Color)
		value.name = "Stat_" + str(spec.key)
		texts.add_child(value)
		_stat_labels[str(spec.key)] = value
		inner.add_child(texts)
		row.add_child(cell)
	return card


func _build_capacity_pill() -> Control:
	var pill := PanelContainer.new()
	pill.name = "CapacityPill"
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.add_theme_stylebox_override("panel", QKit.cut_box("chip_cream", 16, 2))
	var row := UiKit.hbox(6)
	pill.add_child(row)
	var pouch := UiKit.icon("tab_bag", 64)
	pouch.custom_minimum_size = Vector2(64, 64)
	row.add_child(pouch)
	_capacity_label = QKit.title("容量 0 / 20", 30, UiTokens.TEXT)
	_capacity_label.name = "CapacityLabel"
	_capacity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_capacity_label)
	return pill


## 底部按钮：一键出售（没有出售功能 → 「功能暂未开放」）、一键穿戴、分解（打开分解弹窗）、整理。
func _build_capacity_row() -> Control:
	var row := UiKit.hbox(16)
	row.name = "BagActions"
	_sell_button = QKit.button("一键出售", "m", 100, 36)
	_sell_button.name = "SellAllButton"
	_sell_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	LockedFeature.wire(_sell_button, "bag_sell")
	row.add_child(_sell_button)
	_wear_button = QKit.button("一键穿戴", "o", 100, 36)
	_wear_button.name = "WearAllButton"
	_wear_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wear_button.pressed.connect(_on_wear_all)
	row.add_child(_wear_button)
	_salvage_button = QKit.button("分 解", "m", 100, 36)
	_salvage_button.name = "SalvageButton"
	_salvage_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_salvage_button.pressed.connect(func() -> void: action_requested.emit("open_salvage", []))
	row.add_child(_salvage_button)
	_sort_button = QKit.button("整理", "o", 100, 36)
	_sort_button.name = "SortButton"
	_sort_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sort_button.pressed.connect(_tidy)
	row.add_child(_sort_button)
	return row


## 下半薄荷底板的上沿跟着属性卡（设计稿 962）。
func sheet_anchor() -> Control:
	return get_node_or_null("StatsCard") as Control


func sheet_pad() -> float:
	return 12.0


func bind(state: Dictionary, content: Dictionary, item_flags: ItemFlags) -> void:
	_state = state
	_content = content
	flags = item_flags
	# 心跳每次都会 bind：和上次一样就不刷新（v14：原来每次都重建纸娃娃 8 格 + 背包全部格子，滚动被打断、卡顿）。
	var sig := _bind_signature()
	if sig == _bind_sig and is_same(content, _bound_content):
		return
	_bound_content = content
	refresh()


func _bind_signature() -> int:
	var keys := ["items", "power", "hp", "attack", "defense", "speed", "bagCapacity", "enhanceExp", "essence", "realmName"]
	var parts: Array = []
	for key in keys:
		parts.append(_state.get(key, null))
	parts.append(flags.seen.keys() if flags != null else [])
	return hash(parts)


func refresh() -> void:
	_bind_sig = _bind_signature()
	refresh_count += 1
	var seen: Dictionary = flags.seen if flags != null else {}
	model = BagModel.from_state(_state, _content, seen)
	var used := model.used_slots()
	_capacity_label.text = "容量 %d / %d" % [used, model.capacity]
	_capacity_label.add_theme_color_override("font_color", UiTokens.Q_RED if model.is_full() else UiTokens.TEXT)
	_power_value.text = QKit.grouped(float(_state.get("power", 0)))
	for key in _stat_labels:
		(_stat_labels[key] as Label).text = QKit.grouped(float(_state.get(key, 0)))
	var tabs: Array = []
	for entry in TABS:
		tabs.append({"id": entry.id, "name": entry.name})
	_tabs.set_tabs(tabs, category)
	_render_doll()
	_wear_button.disabled = EquipModel.best_upgrades(model).is_empty()
	_render_grid()


func _render_doll() -> void:
	UiKit.clear(_doll_row)
	_cells.clear()
	var slots := EquipModel.slots_of(model)
	for slot in SlotConfig.all():
		var id := str(slot.id)
		var small := bool(slot.get("locked", false))
		var holder := Control.new()
		holder.name = "Holder_" + id
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.top_level = false
		var cell := EquipSlotCell.new()
		cell.make_q(76.0 if small else 150.0)
		cell.setup(slot, slots.get(id, {}))
		cell.slot_pressed.connect(_on_equip_slot)
		holder.add_child(cell)
		var pos: Vector2 = DOLL_POS.get(id, Vector2.ZERO)
		var label_text := str(slot.get("name", "")).replace("头部", "头冠").replace("身体", "衣服").replace("手部", "护腕").replace("腿/鞋", "靴子")
		var label: Control = QKit.tag(label_text, "cream" if small else ("orange" if not slots.get(id, {}).is_empty() else "grey"), 30, 16)
		if small:
			label = QKit.title(label_text, 30, UiTokens.TEXT_MUTED)
		holder.add_child(label)
		_doll_row.add_child(holder)
		holder.set_anchors_preset(Control.PRESET_TOP_LEFT)
		holder.position = pos
		cell.position = Vector2.ZERO
		cell.size = cell.custom_minimum_size
		label.position = Vector2(90, 18) if small else Vector2(75 - label.get_combined_minimum_size().x / 2.0, 150)
		_cells[id] = cell
	_doll_note.text = str(_state.get("realmName", "")) if not str(_state.get("realmName", "")).is_empty() else "装备"


func equip_cell(slot_id: String) -> EquipSlotCell:
	return _cells.get(slot_id, null) as EquipSlotCell


func salvage_button() -> Button:
	return _salvage_button


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


func _on_slot(item: Dictionary) -> void:
	if popup == null:
		return
	var worn := {}
	if str(item.get("category", "")) == "equip":
		worn = EquipModel.worn_in(model, str(item.get("slot_id", "")))
	if detail_popup != null:
		detail_popup.show_view(ItemDetailView.build(item, worn, model, _content, _state), _handlers())
		return
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
		"toast": func(text: String) -> void: action_requested.emit("toast", [text]),
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
	handlers["swap"] = func(_id: String) -> void: _show_picker(slot_id)
	if detail_popup != null:
		detail_popup.show_view(ItemDetailView.build(item, {}, model, _content, _state), handlers)
		return
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
	var unit := "炼器精粹" if model.uses_essence else "强化经验"
	var message := "分解「%s」会得到 %d %s，物品将消失。此操作不能撤销。" % [str(item.name), int(item.get("decompose_exp", 0)), unit]
	if int(item.get("enhance", 0)) > 0:
		message += ("\n含强化返还 +%d。" % (int(item.get("enhance", 0)) * model.enhance.refund_per_level())) if model.uses_essence else "\n已投入的强化经验会按比例返还。"
	ItemDetail.show_confirm(popup, "确认分解", message, "确认分解", func() -> void: action_requested.emit("decompose", [id]))


